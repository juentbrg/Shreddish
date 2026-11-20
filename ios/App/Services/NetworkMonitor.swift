import Network
import Observation

/// État du réseau (spec 017, FR-1702) : bandeau hors ligne et reprise des générations en attente.
@MainActor
@Observable
final class NetworkMonitor {
    private(set) var isOnline = true
    private let monitor = NWPathMonitor()

    init(enabled: Bool) {
        guard enabled else { return }
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "network-monitor"))
    }

    deinit { monitor.cancel() }
}
