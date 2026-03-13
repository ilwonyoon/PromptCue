import AppKit
import Combine
import Foundation
import PromptCueCore

extension Notification.Name {
    static let licenseManagementRequested = Notification.Name("licenseManagementRequested")
}

@MainActor
final class LicensingSettingsModel: ObservableObject, CaptureAccessControlling {
    @Published private(set) var accessSnapshot = AppAccessSnapshot(
        status: .trial(
            TrialStatus(
                startedAt: .now,
                lastSeenAt: .now,
                expiresAt: .now.addingTimeInterval(TrialPolicy.v1.duration),
                daysRemaining: 14
            )
        )
    )
    @Published private(set) var storedLicenseRecord: LicenseActivationRecord?
    @Published var enteredLicenseKey = ""
    @Published private(set) var isActivating = false
    @Published private(set) var activationError: String?

    private let stateStore: any LicensingStateStoring
    private let licenseClient: any LicenseActivationClient
    private let configuration: LicensingConfiguration
    private let accessEvaluator: AppAccessEvaluator
    private let notificationCenter: NotificationCenter
    private let nowProvider: @Sendable () -> Date
    private var qaAccessStateOverride: QAAccessStateOverride?
    private static let accessDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    init(
        stateStore: (any LicensingStateStoring)? = nil,
        configuration: LicensingConfiguration = .current(),
        accessEvaluator: AppAccessEvaluator = AppAccessEvaluator(),
        notificationCenter: NotificationCenter = .default,
        nowProvider: @escaping @Sendable () -> Date = { Date() },
        qaAccessStateOverride: QAAccessStateOverride? = AppEnvironment.current.qaAccessStateOverride,
        licenseClient: (any LicenseActivationClient)? = nil
    ) {
        self.stateStore = stateStore ?? LicensingStateStore.makeDefault()
        self.configuration = configuration
        self.accessEvaluator = accessEvaluator
        self.notificationCenter = notificationCenter
        self.nowProvider = nowProvider
        self.qaAccessStateOverride = qaAccessStateOverride
        self.licenseClient = licenseClient ?? LemonSqueezyLicenseClient(configuration: configuration)
        refresh()
    }

    func refresh() {
        let now = nowProvider()

        if let overrideResolution = qaAccessOverrideResolution(now: now) {
            storedLicenseRecord = nil
            accessSnapshot = overrideResolution.snapshot
            return
        }

        do {
            let trialState = try stateStore.loadTrialState()
            let storedLicenseRecord = try stateStore.loadLicenseRecord()
            let resolution = accessEvaluator.resolve(
                trialState: trialState,
                isLicensed: storedLicenseRecord != nil,
                now: now
            )

            if resolution.trialStateToPersist != trialState {
                try stateStore.saveTrialState(resolution.trialStateToPersist)
            }

            self.storedLicenseRecord = storedLicenseRecord
            accessSnapshot = resolution.snapshot

            if activationError?.hasPrefix("Couldn't read") == true {
                activationError = nil
            }
        } catch {
            let fallbackResolution = accessEvaluator.resolve(
                trialState: nil,
                isLicensed: false,
                now: now
            )
            storedLicenseRecord = nil
            accessSnapshot = fallbackResolution.snapshot
            activationError = "Couldn't read local licensing state. Backtick started a fresh local trial snapshot."
        }
    }

    func activateEnteredLicenseKey() async {
        guard !isActivating else {
            return
        }

        let trimmedKey = enteredLicenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            activationError = "Enter a license key before activating."
            return
        }

        isActivating = true
        activationError = nil
        defer { isActivating = false }

        do {
            let activationRecord = try await licenseClient.activate(
                licenseKey: trimmedKey,
                instanceName: activationInstanceName
            )
            try stateStore.saveLicenseRecord(activationRecord)
            enteredLicenseKey = ""
            refresh()
        } catch {
            activationError = error.localizedDescription
        }
    }

    func openStorefront() {
        guard let storefrontURL = configuration.storefrontURL else {
            activationError = "Purchase link is not configured in this build yet."
            return
        }

        NSWorkspace.shared.open(storefrontURL)
    }

    func handleBlockedCaptureAttempt() {
        notificationCenter.post(name: .licenseManagementRequested, object: nil)
    }

    var accessStatusTitle: String {
        switch accessSnapshot.status {
        case .licensed:
            return "Licensed"
        case .trial(let status):
            return "\(status.daysRemaining) days left"
        case .expired(.trialExpired):
            return "Trial expired"
        case .expired(.clockMovedBackward):
            return "Trial invalidated"
        }
    }

    var accessDetailText: String {
        switch accessSnapshot.status {
        case .licensed:
            let name = storedLicenseRecord?.customerName
                ?? storedLicenseRecord?.customerEmail
                ?? "this Mac"
            return "Backtick is activated for \(name). Capture and save stay unlocked offline."
        case .trial(let status):
            let expiry = Self.accessDateFormatter.string(from: status.expiresAt)
            return "This build is in the full 14-day trial. New capture and save stay unlocked until \(expiry)."
        case .expired(.trialExpired(let expiredAt)):
            let expiry = Self.accessDateFormatter.string(from: expiredAt)
            return "The 14-day trial ended on \(expiry). Existing cards stay visible and export still works, but new saves now require a license."
        case .expired(.clockMovedBackward(let lastSeenAt, _)):
            let seenAt = Self.accessDateFormatter.string(from: lastSeenAt)
            return "Backtick detected the system clock moving backward after \(seenAt). Review and export still work, but new saves now require a license."
        }
    }

    var configurationNote: String? {
        #if DEBUG
        if let qaAccessStateOverride {
            return "QA access override is active (\(qaAccessStateOverride.rawValue)). Remove PROMPTCUE_QA_ACCESS_STATE to resume live trial and licensing state."
        }
        #endif

        if !configuration.isActivationAvailable {
            return "License activation is not configured in this build yet."
        }

        if !configuration.canOpenStorefront {
            return "Purchase link is not configured in this build yet."
        }

        return nil
    }

    var storedLicenseDetailText: String? {
        guard let storedLicenseRecord else {
            return nil
        }

        var detail = "Saved license \(storedLicenseRecord.maskedLicenseKey)"
        if let productName = storedLicenseRecord.productName {
            detail += " for \(productName)"
        }
        if let variantName = storedLicenseRecord.variantName,
           !variantName.isEmpty {
            detail += " (\(variantName))"
        }
        return detail
    }

    var canOpenStorefront: Bool {
        configuration.canOpenStorefront
    }

    var storefrontButtonTitle: String {
        storedLicenseRecord == nil ? "Buy Backtick" : "Open Store Page"
    }

    var activationButtonTitle: String {
        isActivating ? "Activating..." : "Activate"
    }

    var canSubmitLicenseActivation: Bool {
        configuration.isActivationAvailable
            && !isActivating
            && !enteredLicenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var qaAccessStateOverrideSelectionValue: String {
        qaAccessStateOverride?.rawValue ?? "live"
    }

    func setQAAccessStateOverrideSelectionValue(_ selectionValue: String) {
        let normalizedValue = selectionValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedValue == "live" {
            setQAAccessStateOverride(nil)
            return
        }

        setQAAccessStateOverride(QAAccessStateOverride(rawValue: normalizedValue))
    }

    private var activationInstanceName: String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    private func setQAAccessStateOverride(_ override: QAAccessStateOverride?) {
        qaAccessStateOverride = override
        refresh()
    }

    private func qaAccessOverrideResolution(now: Date) -> AppAccessResolution? {
        #if DEBUG
        guard let qaAccessStateOverride else {
            return nil
        }

        let resolution: AppAccessResolution
        switch qaAccessStateOverride {
        case .licensed:
            resolution = AppAccessResolution(
                snapshot: AppAccessSnapshot(status: .licensed),
                trialStateToPersist: nil
            )
        case .trial:
            let startedAt = now.addingTimeInterval(-(2 * 24 * 60 * 60))
            let trialState = TrialState(startedAt: startedAt, lastSeenAt: now)
            let liveResolution = accessEvaluator.resolve(
                trialState: trialState,
                isLicensed: false,
                now: now
            )
            resolution = AppAccessResolution(
                snapshot: liveResolution.snapshot,
                trialStateToPersist: nil
            )
        case .expired:
            let startedAt = now.addingTimeInterval(-(15 * 24 * 60 * 60))
            let trialState = TrialState(startedAt: startedAt, lastSeenAt: now)
            let liveResolution = accessEvaluator.resolve(
                trialState: trialState,
                isLicensed: false,
                now: now
            )
            resolution = AppAccessResolution(
                snapshot: liveResolution.snapshot,
                trialStateToPersist: nil
            )
        case .rollback:
            let startedAt = now.addingTimeInterval(-(24 * 60 * 60))
            let lastSeenAt = now.addingTimeInterval(accessEvaluator.trialPolicy.clockRollbackTolerance + 60)
            let trialState = TrialState(startedAt: startedAt, lastSeenAt: lastSeenAt)
            let liveResolution = accessEvaluator.resolve(
                trialState: trialState,
                isLicensed: false,
                now: now
            )
            resolution = AppAccessResolution(
                snapshot: liveResolution.snapshot,
                trialStateToPersist: nil
            )
        }

        return resolution
        #else
        _ = now
        return nil
        #endif
    }
}
