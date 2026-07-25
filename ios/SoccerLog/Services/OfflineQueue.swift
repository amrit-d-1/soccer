import Foundation

/// A single roster entry captured at New-Session time. It may reference an
/// existing player or describe a brand-new one to be created on sync.
struct QueuedPlayer: Codable, Hashable {
    var existingId: UUID?
    var name: String
    var phone: String?
    var contactId: String?
    var smsOptOut: Bool
}

/// A New-Session save captured locally so it survives a dead pitch signal.
struct QueuedSession: Codable, Identifiable, Hashable {
    var localId: UUID
    var playedAt: String
    var location: String?
    var notes: String?
    var players: [QueuedPlayer]
    var enqueuedAt: Date

    var id: UUID { localId }
}

/// Durable on-disk queue of pending session creations. The actual push logic
/// lives in `DataStore.flushQueue()`; this type only persists and publishes.
@MainActor
final class OfflineQueue: ObservableObject {
    @Published private(set) var pending: [QueuedSession] = []

    private let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("pending_sessions.json")
        load()
    }

    func enqueue(_ item: QueuedSession) {
        pending.append(item)
        persist()
    }

    func remove(_ id: UUID) {
        pending.removeAll { $0.localId == id }
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        pending = (try? JSONDecoder().decode([QueuedSession].self, from: data)) ?? []
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(pending) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
