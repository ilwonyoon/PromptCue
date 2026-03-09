import CloudKit
import Foundation
import PromptCueCore

enum SyncChange: Sendable {
    case upsert(CaptureCard, screenshotAssetURL: URL?)
    case delete(UUID)
}

@MainActor
protocol CloudSyncDelegate: AnyObject {
    func cloudSync(_ engine: CloudSyncEngine, didReceiveChanges changes: [SyncChange])
    func cloudSyncDidComplete(_ engine: CloudSyncEngine)
    func cloudSync(_ engine: CloudSyncEngine, didFailWithError message: String)
}

@MainActor
final class CloudSyncEngine {
    private static let zoneName = "Cards"
    private static let recordType = "CaptureCard"
    private static let serverChangeTokenKey = "CloudSyncEngine.serverChangeToken"

    private let container: CKContainer
    private let database: CKDatabase
    private let zoneID: CKRecordZone.ID
    private let zone: CKRecordZone

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
        do {
            try await createZoneIfNeeded()
            try await subscribeToChanges()
        } catch {
            NSLog("CloudSyncEngine setup failed: %@", String(describing: error))
        }
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
        let record = ckRecord(from: card)

        Task {
            do {
                _ = try await database.save(record)
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
        let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)

        Task {
            do {
                try await database.deleteRecord(withID: recordID)
                delegate?.cloudSyncDidComplete(self)
            } catch let error as CKError where error.code == .unknownItem {
                // Already deleted remotely
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

        let recordsToSave = cards.map { ckRecord(from: $0) }
        let recordIDsToDelete = deletions.map {
            CKRecord.ID(recordName: $0.uuidString, zoneID: zoneID)
        }

        let operation = CKModifyRecordsOperation(
            recordsToSave: recordsToSave,
            recordIDsToDelete: recordIDsToDelete
        )
        operation.savePolicy = .changedKeys
        operation.qualityOfService = .userInitiated

        operation.modifyRecordsResultBlock = { result in
            switch result {
            case .success:
                break
            case .failure(let error):
                NSLog("CloudSync batch push failed: %@", String(describing: error))
            }
        }

        database.add(operation)
    }

    // MARK: - Pull

    func fetchRemoteChanges() {
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
        var changes: [SyncChange] = []

        for record in upserted {
            if let card = captureCard(from: record) {
                let assetURL = (record["screenshot"] as? CKAsset)?.fileURL
                changes.append(.upsert(card, screenshotAssetURL: assetURL))
            }
        }

        for recordID in deleted {
            if let uuid = UUID(uuidString: recordID.recordName) {
                changes.append(.delete(uuid))
            }
        }

        guard !changes.isEmpty else { return }
        delegate?.cloudSync(self, didReceiveChanges: changes)
    }

    private func handleConflict(error: CKError, localCard: CaptureCard) {
        guard let serverRecord = error.serverRecord else {
            return
        }

        let resolved = resolveConflict(local: localCard, remote: serverRecord)
        let record = ckRecord(from: resolved)

        Task {
            do {
                _ = try await database.save(record)
            } catch {
                NSLog("CloudSync conflict resolution save failed: %@", String(describing: error))
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

    private func ckRecord(from card: CaptureCard) -> CKRecord {
        let recordID = CKRecord.ID(recordName: card.id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record["text"] = card.text as NSString
        record["createdAt"] = card.createdAt as NSDate
        record["lastCopiedAt"] = card.lastCopiedAt as NSDate?
        record["sortOrder"] = NSNumber(value: card.sortOrder)

        if let screenshotURL = card.screenshotURL,
           FileManager.default.fileExists(atPath: screenshotURL.path) {
            record["screenshot"] = CKAsset(fileURL: screenshotURL)
        }

        return record
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
