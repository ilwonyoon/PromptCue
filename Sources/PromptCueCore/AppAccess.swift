import Foundation

public struct TrialPolicy: Equatable, Sendable {
    public static let v1 = TrialPolicy(
        duration: 14 * 24 * 60 * 60,
        clockRollbackTolerance: 5 * 60
    )

    public let duration: TimeInterval
    public let clockRollbackTolerance: TimeInterval

    public init(duration: TimeInterval, clockRollbackTolerance: TimeInterval) {
        self.duration = duration
        self.clockRollbackTolerance = clockRollbackTolerance
    }
}

public struct TrialState: Codable, Equatable, Sendable {
    public let startedAt: Date
    public let lastSeenAt: Date

    public init(startedAt: Date, lastSeenAt: Date) {
        self.startedAt = startedAt
        self.lastSeenAt = lastSeenAt
    }

    public func updatingLastSeenAt(_ date: Date) -> TrialState {
        TrialState(startedAt: startedAt, lastSeenAt: date)
    }
}

public struct TrialStatus: Equatable, Sendable {
    public let startedAt: Date
    public let lastSeenAt: Date
    public let expiresAt: Date
    public let daysRemaining: Int

    public init(
        startedAt: Date,
        lastSeenAt: Date,
        expiresAt: Date,
        daysRemaining: Int
    ) {
        self.startedAt = startedAt
        self.lastSeenAt = lastSeenAt
        self.expiresAt = expiresAt
        self.daysRemaining = daysRemaining
    }
}

public enum AccessExpiryReason: Equatable, Sendable {
    case trialExpired(expiredAt: Date)
    case clockMovedBackward(lastSeenAt: Date, currentDate: Date)
}

public enum AppAccessStatus: Equatable, Sendable {
    case licensed
    case trial(TrialStatus)
    case expired(AccessExpiryReason)
}

public struct AppAccessSnapshot: Equatable, Sendable {
    public let status: AppAccessStatus

    public init(status: AppAccessStatus) {
        self.status = status
    }

    public var allowsCaptureSave: Bool {
        switch status {
        case .licensed, .trial:
            return true
        case .expired:
            return false
        }
    }

    public var allowsReadAccess: Bool {
        true
    }

    public var allowsExport: Bool {
        true
    }

    public var allowsLicenseManagement: Bool {
        true
    }
}

public struct AppAccessResolution: Equatable, Sendable {
    public let snapshot: AppAccessSnapshot
    public let trialStateToPersist: TrialState?

    public init(snapshot: AppAccessSnapshot, trialStateToPersist: TrialState?) {
        self.snapshot = snapshot
        self.trialStateToPersist = trialStateToPersist
    }
}

public struct AppAccessEvaluator: Sendable {
    public let trialPolicy: TrialPolicy

    public init(trialPolicy: TrialPolicy = .v1) {
        self.trialPolicy = trialPolicy
    }

    public func resolve(
        trialState: TrialState?,
        isLicensed: Bool,
        now: Date = .now
    ) -> AppAccessResolution {
        if isLicensed {
            return AppAccessResolution(
                snapshot: AppAccessSnapshot(status: .licensed),
                trialStateToPersist: trialState
            )
        }

        let persistedTrialState = trialState ?? TrialState(startedAt: now, lastSeenAt: now)

        if now.addingTimeInterval(trialPolicy.clockRollbackTolerance) < persistedTrialState.lastSeenAt {
            return AppAccessResolution(
                snapshot: AppAccessSnapshot(
                    status: .expired(
                        .clockMovedBackward(
                            lastSeenAt: persistedTrialState.lastSeenAt,
                            currentDate: now
                        )
                    )
                ),
                trialStateToPersist: persistedTrialState
            )
        }

        let updatedTrialState: TrialState
        if persistedTrialState.lastSeenAt < now {
            updatedTrialState = persistedTrialState.updatingLastSeenAt(now)
        } else {
            updatedTrialState = persistedTrialState
        }

        let expiresAt = updatedTrialState.startedAt.addingTimeInterval(trialPolicy.duration)
        if now >= expiresAt {
            return AppAccessResolution(
                snapshot: AppAccessSnapshot(status: .expired(.trialExpired(expiredAt: expiresAt))),
                trialStateToPersist: updatedTrialState
            )
        }

        let secondsRemaining = expiresAt.timeIntervalSince(now)
        let daysRemaining = max(1, Int(ceil(secondsRemaining / (24 * 60 * 60))))

        return AppAccessResolution(
            snapshot: AppAccessSnapshot(
                status: .trial(
                    TrialStatus(
                        startedAt: updatedTrialState.startedAt,
                        lastSeenAt: updatedTrialState.lastSeenAt,
                        expiresAt: expiresAt,
                        daysRemaining: daysRemaining
                    )
                )
            ),
            trialStateToPersist: updatedTrialState
        )
    }
}
