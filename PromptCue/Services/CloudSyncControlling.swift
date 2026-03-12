import Foundation
import PromptCueCore

@MainActor
protocol CloudSyncControlling: AnyObject {
    var delegate: CloudSyncDelegate? { get set }

    func setup() async
    func stop()
    func fetchRemoteChanges()
    func handleRemoteNotification()
    func pushLocalChange(card: CaptureCard)
    func pushDeletion(id: UUID)
    func pushBatch(cards: [CaptureCard], deletions: [UUID])
}
