import Foundation
import Network
import Combine

/// Observes network reachability so queued writes can flush when signal returns.
@MainActor
final class Connectivity: ObservableObject {
    static let shared = Connectivity()

    @Published private(set) var isOnline: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "connectivity.monitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = (path.status == .satisfied)
            }
        }
        monitor.start(queue: queue)
    }
}
