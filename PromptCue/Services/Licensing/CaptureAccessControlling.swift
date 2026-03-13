import Foundation
import PromptCueCore

@MainActor
protocol CaptureAccessControlling: AnyObject {
    var accessSnapshot: AppAccessSnapshot { get }
    func handleBlockedCaptureAttempt()
}

@MainActor
final class AllowAllCaptureAccessController: CaptureAccessControlling {
    let accessSnapshot = AppAccessSnapshot(status: .licensed)

    func handleBlockedCaptureAttempt() {}
}
