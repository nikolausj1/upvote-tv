import Foundation

struct QueueItem: Identifiable, Codable, Hashable {
    let id: String
    let url: URL
    let source: QueueSource
    let sharedAt: Date
}
