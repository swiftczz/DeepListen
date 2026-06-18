import Foundation

extension Notification.Name {
    static let didReceiveMediaURLs = Notification.Name("IELTSListeningTrainer.didReceiveMediaURLs")
    static let didRequestSettingsWindow = Notification.Name("IELTSListeningTrainer.didRequestSettingsWindow")
}

@MainActor
final class OpenFileCoordinator {
    static let shared = OpenFileCoordinator()

    private var pendingURLs: [URL] = []

    private init() {}

    func receive(_ urls: [URL]) {
        let playableURLs = urls.filter { PlayerStore.isPlayableMediaURL($0) }
        guard !playableURLs.isEmpty else { return }

        pendingURLs.append(contentsOf: playableURLs)
        NotificationCenter.default.post(name: .didReceiveMediaURLs, object: playableURLs)
    }

    func drainPendingURLs() -> [URL] {
        let urls = pendingURLs
        pendingURLs.removeAll()
        return urls
    }
}
