import CloudKit
import Foundation
import Network
import PromptCueCore

enum SyncChange: Sendable {
    case upsert(CaptureCard, screenshotAssetURL: URL?)
    case delete(UUID)
}

enum CloudSyncAccountStatus: Sendable {
    case available
    case noAccount
    case restricted
    case unknown
}

@MainActor
protocol CloudSyncDelegate: AnyObject {
    func cloudSync(_ engine: CloudSyncEngine, didReceiveChanges changes: [SyncChange])
    func cloudSyncDidComplete(_ engine: CloudSyncEngine)
    func cloudSync(_ engine: CloudSyncEngine, didFailWithError message: String)
    func cloudSync(_ engine: CloudSyncEngine, accountStatusChanged status: CloudSyncAccountStatus)
}

@MainActor
final class CloudSyncEngine: CloudSyncControlling {
    private static let zoneName = "Cards"
    private static let recordType = "CaptureCard"
    private static let serverChangeTokenKey = "CloudSyncEngine.serverChangeToken"
    private static let maxRetryAttempts = 3

    private let container: CKContainer
    private let database: CKDatabase
    private let zoneID: CKRecordZone.ID
    private let zone: CKRecordZone
    private var recentlyPushedIDs = Set<UUID>()
    private var isFetching = false
    private var networkMonitor: NWPathMonitor?
    private(set) var isNetworkAvailable = true
    private(set) var accountStatus: CloudSyncAccountStatus = .unknown

    weak var delegate: CloudSyncDelegate?

    private var serverChangeToken: CKServerChangeToken? {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.serverChangeTokenKey) else {
                return nil
            }
            return try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: CKServerChangeToken.self,
                from: data
            )
        }
        set {
            if let token = newValue,
               let data = try? NSKeyedArchiver.archivedData(
                   withRootObject: token,
                   requiringSecureCoding: true
               ) {
                UserDefaults.standard.set(data, forKey: Self.serverChangeTokenKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.serverChangeTokenKey)
            }
        }
    }

    init(containerIdentifier: String = "iCloud.com.promptcue.promptcue") {
        container = CKContainer(identifier: containerIdentifier)
        database = container.privateCloudDatabase
        zoneID = CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
        zone = CKRecordZone(zoneID: zoneID)
    }

    // MARK: - Setup

    func setup() async {
        startNetworkMonitor()

        let status = await checkAccountStatus()
        accountStatus = status
        delegate?.cloudSync(self, accountStatusChanged: status)

        guard status == .available else {
            let message: String
            switch status {
            case .noAccount:
                message = "No iCloud account. Sign in via System Settings."
            case .restricted:
                message = "iCloud access is restricted on this device."
            case .unknown, .available:
                message = "Unable to verify iCloud account status."
            }
            delegate?.cloudSync(self, didFailWithError: message)
            return
        }

        do {
            try await createZoneIfNeeded()
            try await subscribeToChanges()
        } catch {
            NSLog("CloudSyncEngine setup failed: %@", String(describing: error))
            delegate?.cloudSync(self, didFailWithError: error.localizedDescription)
        }
    }

    func stop() {
        stopNetworkMonitor()
        isFetching = false
    }

    private func checkAccountStatus() async -> CloudSyncAccountStatus {
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                return .available
            case .noAccount:
                return .noAccount
            case .restricted:
                return .restricted
            case .couldNotDetermine, .temporarilyUnavailable:
                return .unknown
            @unknown default:
                return .unknown
            }
        } catch {
            NSLog("CloudSync account status check failed: %@", String(describing: error))
            return .unknown
        }
    }

    private func startNetworkMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.isNetworkAvailable = path.status == .satisfied
            }
        }
        monitor.start(queue: DispatchQueue(label: "CloudSyncEngine.network"))
        networkMonitor = monitor
    }

    func stopNetworkMonitor() {
        networkMonitor?.cancel()
        networkMonitor = nil
    }

    private func createZoneIfNeeded() async throws {
        do {
            _ = try await database.save(zone)
        } catch let error as CKError where error.code == .serverRejectedRequest {
            // Zone already exists
        }
    }

    private func subscribeToChanges() async throws {
        let subscriptionID = "card-changes"

        do {
            _ = try await database.subscription(for: subscriptionID)
            return
        } catch {
            // Subscription doesn't exist, create it
        }

        let subscription = CKRecordZoneSubscription(
            zoneID: zoneID,
            subscriptionID: subscriptionID
        )
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        _ = try await database.save(subscription)
    }

    // MARK: - Push

    func pushLocalChange(card: CaptureCard) {
        recentlyPushedIDs.insert(card.id)

        guard isNetworkAvailable else {
            NSLog("CloudSync push skipped (offline) for %@", card.id.uuidString)
            return
        }

        Task {
            do {
                try await retryOnTransientError {
                    let record = try await self.fetchOrCreateRecord(for: card)
                    self.applyCardFields(card, to: record)
                    _ = try await self.database.save(record)
                }
                delegate?.cloudSyncDidComplete(self)
            } catch let error as CKError where error.code == .serverRecordChanged {
                handleConflict(error: error, localCard: card)
            } catch {
                NSLog("CloudSync push failed for %@: %@", card.id.uuidString, String(describing: error))
                delegate?.cloudSync(self, didFailWithError: error.localizedDescription)
            }
        }
    }

    func pushDeletion(id: UUID) {
        recentlyPushedIDs.insert(id)

        guard isNetworkAvailable else {
            NSLog("CloudSync delete skipped (offline) for %@", id.uuidString)
            return
        }

        let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)

        Task {
            do {
                try await retryOnTransientError {
                    try await self.database.deleteRecord(withID: recordID)
                }
                delegate?.cloudSyncDidComplete(self)
            } catch let error as CKError where error.code == .unknownItem {
                delegate?.cloudSyncDidComplete(self)
            } catch {
                NSLog("CloudSync delete failed for %@: %@", id.uuidString, String(describing: error))
                delegate?.cloudSync(self, didFailWithError: error.localizedDescription)
            }
        }
    }

    func pushBatch(cards: [CaptureCard], deletions: [UUID]) {
        guard !cards.isEmpty || !deletions.isEmpty else {
            return
        }

        for card in cards {
            recentlyPushedIDs.insert(card.id)
        }
        for id in deletions {
            recentlyPushedIDs.insert(id)
        }

        let recordsToSave = cards.map { newRecord(from: $0) }
        let recordIDsToDelete = deletions.map {
            CKRecord.ID(recordName: $0.uuidString, zoneID: zoneID)
        }

        let operation = CKModifyRecordsOperation(
            recordsToSave: recordsToSave,
            recordIDsToDelete: recordIDsToDelete
        )
        operation.savePolicy = .changedKeys
        operation.qualityOfService = .userInitiated

        operation.modifyRecordsResultBlock = { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch result {
                case .success:
                    self.delegate?.cloudSyncDidComplete(self)
                case .failure(let error):
                    NSLog("CloudSync batch push failed: %@", String(describing: error))
                    self.delegate?.cloudSync(self, didFailWithError: error.localizedDescription)
                }
            }
        }

        database.add(operation)
    }

    // MARK: - Pull

    func fetchRemoteChanges() {
        guard !isFetching else { return }
        guard isNetworkAvailable else { return }
        isFetching = true

        let options = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        options.previousServerChangeToken = serverChangeToken

        let operation = CKFetchRecordZoneChangesOperation(
            recordZoneIDs: [zoneID],
            configurationsByRecordZoneID: [zoneID: options]
        )

        var upsertedRecords: [CKRecord] = []
        var deletedRecordIDs: [CKRecord.ID] = []

        operation.recordWasChangedBlock = { _, result in
            switch result {
            case .success(let record):
                upsertedRecords.append(record)
            case .failure(let error):
                NSLog("CloudSync fetch record error: %@", String(describing: error))
            }
        }

        operation.recordWithIDWasDeletedBlock = { recordID, _ in
            deletedRecordIDs.append(recordID)
        }

        operation.recordZoneChangeTokensUpdatedBlock = { [weak self] _, token, _ in
            Task { @MainActor [weak self] in
                self?.serverChangeToken = token
            }
        }

        operation.recordZoneFetchResultBlock = { [weak self] _, result in
            Task { @MainActor [weak self] in
                guard let self else { return }

                self.isFetching = false

                switch result {
                case .success(let (token, _, _)):
                    self.serverChangeToken = token
                    self.processRemoteChanges(
                        upserted: upsertedRecords,
                        deleted: deletedRecordIDs
                    )
                    self.delegate?.cloudSyncDidComplete(self)
                case .failure(let error):
                    if let ckError = error as? CKError, ckError.code == .changeTokenExpired {
                        self.serverChangeToken = nil
                        self.fetchRemoteChanges()
                    } else {
                        NSLog("CloudSync fetch zone failed: %@", String(describing: error))
                        self.delegate?.cloudSync(self, didFailWithError: error.localizedDescription)
                    }
                }
            }
        }

        operation.qualityOfService = .userInitiated
        database.add(operation)
    }

    // MARK: - Remote Notification

    func handleRemoteNotification() {
        fetchRemoteChanges()
    }

    // MARK: - Private

    private func processRemoteChanges(upserted: [CKRecord], deleted: [CKRecord.ID]) {
        let echoIDs = recentlyPushedIDs
        recentlyPushedIDs.removeAll()

        var changes: [SyncChange] = []

        for record in upserted {
            guard let card = captureCard(from: record) else { continue }
            guard !echoIDs.contains(card.id) else { continue }
            let assetURL = (record["screenshot"] as? CKAsset)?.fileURL
            changes.append(.upsert(card, screenshotAssetURL: assetURL))
        }

        for recordID in deleted {
            guard let uuid = UUID(uuidString: recordID.recordName) else { continue }
            guard !echoIDs.contains(uuid) else { continue }
            changes.append(.delete(uuid))
        }

        guard !changes.isEmpty else { return }
        delegate?.cloudSync(self, didReceiveChanges: changes)
    }

    private func handleConflict(error: CKError, localCard: CaptureCard) {
        guard let serverRecord = error.serverRecord else {
            return
        }

        let resolved = resolveConflict(local: localCard, remote: serverRecord)
        applyCardFields(resolved, to: serverRecord)

        Task {
            do {
                _ = try await database.save(serverRecord)
                delegate?.cloudSyncDidComplete(self)
            } catch {
                NSLog("CloudSync conflict resolution save failed: %@", String(describing: error))
                delegate?.cloudSync(self, didFailWithError: error.localizedDescription)
            }
        }
    }

    private func resolveConflict(local: CaptureCard, remote: CKRecord) -> CaptureCard {
        let remoteLastCopied = remote["lastCopiedAt"] as? Date
        let localLastCopied = local.lastCopiedAt

        // If either has been copied more recently, that version wins
        switch (localLastCopied, remoteLastCopied) {
        case (.some(let localDate), .some(let remoteDate)):
            return localDate >= remoteDate ? local : captureCard(from: remote) ?? local
        case (.some, .none):
            return local
        case (.none, .some):
            return captureCard(from: remote) ?? local
        case (.none, .none):
            return local
        }
    }

    // MARK: - CKRecord Mapping

    private func fetchOrCreateRecord(for card: CaptureCard) async throws -> CKRecord {
        let recordID = CKRecord.ID(recordName: card.id.uuidString, zoneID: zoneID)
        do {
            return try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            return CKRecord(recordType: Self.recordType, recordID: recordID)
        }
    }

    private func applyCardFields(_ card: CaptureCard, to record: CKRecord) {
        record["text"] = card.text as NSString
        record["createdAt"] = card.createdAt as NSDate
        record["lastCopiedAt"] = card.lastCopiedAt as NSDate?
        record["sortOrder"] = NSNumber(value: card.sortOrder)

        if let screenshotURL = ManagedScreenshotAccess.readableURL(for: card),
           FileManager.default.fileExists(atPath: screenshotURL.path) {
            record["screenshot"] = CKAsset(fileURL: screenshotURL)
        }
    }

    private func newRecord(from card: CaptureCard) -> CKRecord {
        let recordID = CKRecord.ID(recordName: card.id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        applyCardFields(card, to: record)
        return record
    }

    private func retryOnTransientError(
        attempt: Int = 0,
        operation: @escaping () async throws -> Void
    ) async throws {
        do {
            try await operation()
        } catch let error as CKError where isRetryableError(error) && attempt < Self.maxRetryAttempts {
            let delay = error.retryAfterSeconds ?? Double(attempt + 1) * 2.0
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            try await retryOnTransientError(attempt: attempt + 1, operation: operation)
        }
    }

    private func isRetryableError(_ error: CKError) -> Bool {
        switch error.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable,
             .requestRateLimited, .zoneBusy:
            return true
        default:
            return false
        }
    }

    private func captureCard(from record: CKRecord) -> CaptureCard? {
        guard let text = record["text"] as? String,
              let createdAt = record["createdAt"] as? Date,
              let uuid = UUID(uuidString: record.recordID.recordName)
        else {
            return nil
        }

        return CaptureCard(
            id: uuid,
            text: text,
            createdAt: createdAt,
            screenshotPath: nil,
            lastCopiedAt: record["lastCopiedAt"] as? Date,
            sortOrder: (record["sortOrder"] as? Double) ?? createdAt.timeIntervalSinceReferenceDate
        )
    }
}
