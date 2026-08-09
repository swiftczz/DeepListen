import Foundation

struct PersistedPlayerLibrary {
    var tracks: [ListeningTrack]
    var selectedTrackID: ListeningTrack.ID?
    var needsRewrite: Bool
}

struct PlayerPersistence {
    private enum Keys {
        static let storedTracks = "libraryTracks"
        static let selectedTrackID = "selectedTrackID"
        static let playbackRate = "playbackRate"
        static let playbackMode = "playbackMode"
        static let showSubtitles = "showSubtitles"
        static let showSubtitleContext = "showSubtitleContext"
    }

    private struct StoredTrack: Codable {
        var id: UUID
        var path: String
        /// 可选类型保持对旧版媒体库数据的兼容。
        var duration: TimeInterval?
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var playbackRate: Double {
        let storedRate = defaults.double(forKey: Keys.playbackRate)
        return storedRate >= 0.25 ? min(2.0, storedRate) : 1.0
    }

    var playbackMode: PlaybackMode {
        PlaybackMode(rawValue: defaults.string(forKey: Keys.playbackMode) ?? "")
            ?? .sequence
    }

    var showSubtitles: Bool {
        storedBool(forKey: Keys.showSubtitles, fallback: true)
    }

    var showSubtitleContext: Bool {
        storedBool(forKey: Keys.showSubtitleContext, fallback: true)
    }

    func savePlaybackRate(_ rate: Double) {
        defaults.set(rate, forKey: Keys.playbackRate)
    }

    func savePlaybackMode(_ mode: PlaybackMode) {
        defaults.set(mode.rawValue, forKey: Keys.playbackMode)
    }

    func saveShowSubtitles(_ isShown: Bool) {
        defaults.set(isShown, forKey: Keys.showSubtitles)
    }

    func saveShowSubtitleContext(_ isShown: Bool) {
        defaults.set(isShown, forKey: Keys.showSubtitleContext)
    }

    func loadLibrary() -> PersistedPlayerLibrary {
        guard
            let data = defaults.data(forKey: Keys.storedTracks),
            let storedTracks = try? JSONDecoder().decode([StoredTrack].self, from: data)
        else {
            return PersistedPlayerLibrary(
                tracks: [],
                selectedTrackID: nil,
                needsRewrite: false
            )
        }

        let tracks = deduplicatedTracks(storedTracks.compactMap { storedTrack in
            let url = URL(filePath: storedTrack.path)
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)),
                MediaDiscoveryService.isPlayableMediaURL(url)
            else {
                return nil
            }
            return ListeningTrack(
                url: url,
                id: storedTrack.id,
                duration: storedTrack.duration
            )
        })

        let selectedTrackID: ListeningTrack.ID?
        if let selectedIDString = defaults.string(forKey: Keys.selectedTrackID),
            let selectedID = UUID(uuidString: selectedIDString),
            tracks.contains(where: { $0.id == selectedID })
        {
            selectedTrackID = selectedID
        } else {
            selectedTrackID = tracks.first?.id
        }

        return PersistedPlayerLibrary(
            tracks: tracks,
            selectedTrackID: selectedTrackID,
            needsRewrite: tracks.count != storedTracks.count
        )
    }

    func saveLibrary(
        tracks: [ListeningTrack],
        selectedTrackID: ListeningTrack.ID?
    ) {
        let storedTracks = tracks.map {
            StoredTrack(
                id: $0.id,
                path: $0.url.path(percentEncoded: false),
                duration: $0.duration
            )
        }
        if let data = try? JSONEncoder().encode(storedTracks) {
            defaults.set(data, forKey: Keys.storedTracks)
        }

        if let selectedTrackID {
            defaults.set(selectedTrackID.uuidString, forKey: Keys.selectedTrackID)
        } else {
            defaults.removeObject(forKey: Keys.selectedTrackID)
        }
    }

    private func storedBool(forKey key: String, fallback: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return defaults.bool(forKey: key)
    }

    private func deduplicatedTracks(_ tracks: [ListeningTrack]) -> [ListeningTrack] {
        var knownMediaKeys = Set<String>()
        return tracks.filter { track in
            knownMediaKeys.insert(
                MediaDiscoveryService.mediaIdentityKey(for: track.url)
            ).inserted
        }
    }
}
