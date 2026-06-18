import AppKit
import AVFoundation
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class PlayerStore: NSObject, ObservableObject {
    @Published private(set) var tracks: [ListeningTrack] = []
    @Published var selectedTrackID: ListeningTrack.ID?
    @Published private(set) var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published private(set) var playbackRate: Double = PlayerStore.defaultPlaybackRate()
    @Published var playbackMode: PlaybackMode = PlayerStore.defaultPlaybackMode() {
        didSet {
            UserDefaults.standard.set(playbackMode.rawValue, forKey: Keys.playbackMode)
        }
    }
    @Published var showSubtitles: Bool = PlayerStore.defaultBool(Keys.showSubtitles, fallback: true) {
        didSet {
            UserDefaults.standard.set(showSubtitles, forKey: Keys.showSubtitles)
        }
    }
    @Published var showSubtitleContext: Bool = PlayerStore.defaultBool(Keys.showSubtitleContext, fallback: true) {
        didSet {
            UserDefaults.standard.set(showSubtitleContext, forKey: Keys.showSubtitleContext)
        }
    }
    @Published private(set) var subtitleCues: [SubtitleCue] = []
    @Published private(set) var currentSubtitleIndex: Int?
    @Published var loopStart: TimeInterval?
    @Published var loopEnd: TimeInterval?

    let player = AVPlayer()

    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()

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
    }

    override init() {
        super.init()
        configurePlayer()
        configureOpenFileHandling()
        loadPersistedLibrary()

        if tracks.isEmpty {
            addDefaultAudioIfAvailable()
        }

        if selectedTrackID == nil {
            selectedTrackID = tracks.first?.id
        }

        if selectedTrackID != nil {
            loadCurrentTrack(autoplay: false)
        }
    }

    var selectedTrack: ListeningTrack? {
        tracks.first { $0.id == selectedTrackID }
    }

    var selectedIndex: Int? {
        guard let selectedTrackID else { return nil }
        return tracks.firstIndex { $0.id == selectedTrackID }
    }

    var currentSubtitle: SubtitleCue? {
        guard let currentSubtitleIndex, subtitleCues.indices.contains(currentSubtitleIndex) else {
            return nil
        }
        return subtitleCues[currentSubtitleIndex]
    }

    var previousSubtitle: SubtitleCue? {
        if let currentSubtitleIndex, currentSubtitleIndex > 0 {
            return subtitleCues[currentSubtitleIndex - 1]
        }

        return subtitleCues.last { $0.end < currentTime }
    }

    var nextSubtitle: SubtitleCue? {
        if let currentSubtitleIndex, subtitleCues.indices.contains(currentSubtitleIndex + 1) {
            return subtitleCues[currentSubtitleIndex + 1]
        }

        return subtitleCues.first { $0.start > currentTime }
    }

    var loopSummary: String {
        switch (loopStart, loopEnd) {
        case let (start?, end?) where end > start:
            return "\(start.formattedPlaybackTime) - \(end.formattedPlaybackTime)"
        case let (start?, _):
            return "A \(start.formattedPlaybackTime) 已设置"
        default:
            return "片段未设置"
        }
    }

    func showImportFilesPanel() {
        let panel = NSOpenPanel()
        panel.title = "导入听力文件"
        panel.prompt = "导入"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio, .movie]

        if panel.runModal() == .OK {
            addURLs(panel.urls, autoplayFirst: false)
        }
    }

    func showImportMediaPanel() {
        let panel = NSOpenPanel()
        panel.title = "添加听力文件或目录"
        panel.prompt = "添加"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio, .movie]

        if panel.runModal() == .OK {
            addURLs(panel.urls, autoplayFirst: false)
        }
    }

    func showImportFolderPanel() {
        let panel = NSOpenPanel()
        panel.title = "导入听力目录"
        panel.prompt = "导入"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK {
            addURLs(panel.urls, autoplayFirst: false)
        }
    }

    @discardableResult
    func addURLs(_ urls: [URL], autoplayFirst: Bool) -> [ListeningTrack] {
        let mediaURLs = Self.discoverPlayableMediaURLs(from: urls)
        guard !mediaURLs.isEmpty else { return [] }

        var firstTargetID: UUID?
        var addedTracks: [ListeningTrack] = []
        var knownMediaKeys = Set(tracks.map { Self.mediaIdentityKey(for: $0.url) })

        for mediaURL in mediaURLs {
            let mediaKey = Self.mediaIdentityKey(for: mediaURL)

            if let existingTrack = tracks.first(where: { Self.mediaIdentityKey(for: $0.url) == mediaKey }) {
                if firstTargetID == nil {
                    firstTargetID = existingTrack.id
                }
                continue
            }

            guard knownMediaKeys.insert(mediaKey).inserted else { continue }

            let track = ListeningTrack(url: mediaURL)
            addedTracks.append(track)
            if firstTargetID == nil {
                firstTargetID = track.id
            }
        }

        guard !addedTracks.isEmpty || firstTargetID != nil else { return [] }

        tracks.append(contentsOf: addedTracks)
        tracks.sort {
            $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
        }
        refreshDurations(for: addedTracks)

        if selectedTrackID == nil, let firstTrack = tracks.first {
            selectTrack(firstTrack.id, autoplay: false)
        }

        if autoplayFirst, let firstTargetID {
            selectTrack(firstTargetID, autoplay: true)
        }

        persistLibrary()
        return addedTracks
    }

    func openExternalURLs(_ urls: [URL]) {
        addURLs(urls, autoplayFirst: true)
    }

    func selectTrack(_ id: ListeningTrack.ID, autoplay: Bool) {
        guard tracks.contains(where: { $0.id == id }) else { return }

        if selectedTrackID == id {
            if autoplay {
                play()
            }
            return
        }

        selectedTrackID = id
        UserDefaults.standard.set(id.uuidString, forKey: Keys.selectedTrackID)
        loadCurrentTrack(autoplay: autoplay)
        persistLibrary()
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func play() {
        if player.currentItem == nil {
            if selectedTrackID == nil {
                selectedTrackID = tracks.first?.id
            }
            loadCurrentTrack(autoplay: false)
        }

        guard player.currentItem != nil else { return }

        if duration > 0, currentTime >= duration {
            seek(to: 0)
        }

        isPlaying = true
        player.playImmediately(atRate: Float(playbackRate))
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func nextTrack() {
        guard !tracks.isEmpty else { return }
        let nextIndex = ((selectedIndex ?? -1) + 1) % tracks.count
        selectTrack(tracks[nextIndex].id, autoplay: isPlaying)
    }

    func previousTrack() {
        guard !tracks.isEmpty else { return }
        let currentIndex = selectedIndex ?? 0
        let previousIndex = (currentIndex - 1 + tracks.count) % tracks.count
        selectTrack(tracks[previousIndex].id, autoplay: isPlaying)
    }

    func seek(to seconds: TimeInterval) {
        let clampedSeconds = max(0, min(seconds, max(duration, seconds)))
        currentTime = clampedSeconds
        updateSubtitleIndex(at: clampedSeconds)
        player.seek(
            to: CMTime(seconds: clampedSeconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    func skip(by seconds: TimeInterval) {
        seek(to: currentTime + seconds)
        if isPlaying {
            player.playImmediately(atRate: Float(playbackRate))
        }
    }

    func setPlaybackRate(_ rate: Double) {
        let stepped = (rate / 0.25).rounded() * 0.25
        let clamped = min(2.0, max(0.25, stepped))
        playbackRate = clamped
        UserDefaults.standard.set(clamped, forKey: Keys.playbackRate)

        if isPlaying {
            player.rate = Float(clamped)
        }
    }

    func setLoopStart() {
        loopStart = currentTime
        if let loopEnd, loopEnd <= currentTime {
            self.loopEnd = nil
        }
    }

    func setLoopEnd() {
        guard let loopStart else {
            self.loopStart = currentTime
            return
        }

        if currentTime > loopStart {
            loopEnd = currentTime
        }
    }

    func clearLoop() {
        loopStart = nil
        loopEnd = nil
    }

    func removeTrack(_ id: ListeningTrack.ID) {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        let removedSelectedTrack = tracks[index].id == selectedTrackID
        tracks.remove(at: index)

        if removedSelectedTrack {
            pause()
            player.replaceCurrentItem(with: nil)
            selectedTrackID = tracks.indices.contains(index) ? tracks[index].id : tracks.first?.id
            loadCurrentTrack(autoplay: false)
        }

        persistLibrary()
    }

    func clearLibrary() {
        pause()
        player.replaceCurrentItem(with: nil)
        tracks.removeAll()
        selectedTrackID = nil
        subtitleCues.removeAll()
        currentSubtitleIndex = nil
        currentTime = 0
        duration = 0
        loopStart = nil
        loopEnd = nil
        persistLibrary()
    }

    func reloadDefaultLibrary() {
        clearLibrary()
        addDefaultAudioIfAvailable()
        if let firstTrack = tracks.first {
            selectTrack(firstTrack.id, autoplay: false)
        }
    }

    func revealInFinder(_ track: ListeningTrack) {
        NSWorkspace.shared.activateFileViewerSelecting([track.url])
    }

    static func isPlayableMediaURL(_ url: URL) -> Bool {
        let playableExtensions: Set<String> = [
            "mp3", "m4a", "aac", "wav", "aiff", "aif", "caf", "flac",
            "mp4", "m4v", "mov", "avi", "mkv"
        ]
        return playableExtensions.contains(url.pathExtension.lowercased())
    }

    private func configurePlayer() {
        player.automaticallyWaitsToMinimizeStalling = false

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.08, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                self?.handlePlaybackTick(time.seconds)
            }
        }

        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
            .sink { [weak self] notification in
                Task { @MainActor in
                    self?.handlePlaybackFinished(notification)
                }
            }
            .store(in: &cancellables)
    }

    private func configureOpenFileHandling() {
        NotificationCenter.default.publisher(for: .didReceiveMediaURLs)
            .compactMap { $0.object as? [URL] }
            .sink { [weak self] urls in
                Task { @MainActor in
                    self?.openExternalURLs(urls)
                }
            }
            .store(in: &cancellables)

        let pendingURLs = OpenFileCoordinator.shared.drainPendingURLs()
        if !pendingURLs.isEmpty {
            openExternalURLs(pendingURLs)
        }
    }

    private func loadCurrentTrack(autoplay: Bool) {
        guard let selectedTrack else {
            player.replaceCurrentItem(with: nil)
            subtitleCues.removeAll()
            currentSubtitleIndex = nil
            currentTime = 0
            duration = 0
            return
        }

        player.replaceCurrentItem(with: AVPlayerItem(url: selectedTrack.url))
        isPlaying = false
        currentTime = 0
        duration = selectedTrack.duration ?? 0
        loopStart = nil
        loopEnd = nil
        loadSubtitles(for: selectedTrack)

        refreshDurations(for: [selectedTrack])

        if autoplay {
            play()
        }
    }

    private func loadSubtitles(for track: ListeningTrack) {
        guard let subtitleURL = track.subtitleURL else {
            subtitleCues = []
            currentSubtitleIndex = nil
            return
        }

        subtitleCues = SRTParser.parse(url: subtitleURL)
        updateSubtitleIndex(at: currentTime)
    }

    private func handlePlaybackTick(_ seconds: TimeInterval) {
        guard seconds.isFinite else { return }

        if let itemDuration = player.currentItem?.duration.seconds, itemDuration.isFinite, itemDuration > 0 {
            duration = itemDuration
        }

        currentTime = seconds
        updateSubtitleIndex(at: seconds)

        if let loopStart, let loopEnd, loopEnd > loopStart, seconds >= loopEnd {
            seek(to: loopStart)
            if isPlaying {
                player.playImmediately(atRate: Float(playbackRate))
            }
        }
    }

    private func handlePlaybackFinished(_ notification: Notification) {
        if let endedItem = notification.object as? AVPlayerItem, endedItem !== player.currentItem {
            return
        }

        if let loopStart, let loopEnd, loopEnd > loopStart {
            seek(to: loopStart)
            play()
            return
        }

        switch playbackMode {
        case .singleLoop:
            seek(to: 0)
            play()
        case .sequence:
            guard let currentIndex = selectedIndex, currentIndex + 1 < tracks.count else {
                pause()
                seek(to: 0)
                return
            }
            selectTrack(tracks[currentIndex + 1].id, autoplay: true)
        }
    }

    private func updateSubtitleIndex(at seconds: TimeInterval) {
        currentSubtitleIndex = subtitleCues.firstIndex { cue in
            cue.start <= seconds && seconds <= cue.end
        }
    }

    private func loadPersistedLibrary() {
        guard
            let data = UserDefaults.standard.data(forKey: Keys.storedTracks),
            let storedTracks = try? JSONDecoder().decode([StoredTrack].self, from: data)
        else {
            return
        }

        var knownMediaKeys = Set<String>()
        tracks = storedTracks.compactMap { storedTrack in
            let url = URL(fileURLWithPath: storedTrack.path)
            guard FileManager.default.fileExists(atPath: url.path), Self.isPlayableMediaURL(url) else {
                return nil
            }
            let mediaKey = Self.mediaIdentityKey(for: url)
            guard knownMediaKeys.insert(mediaKey).inserted else { return nil }
            return ListeningTrack(url: url, id: storedTrack.id)
        }

        if
            let selectedIDString = UserDefaults.standard.string(forKey: Keys.selectedTrackID),
            let selectedID = UUID(uuidString: selectedIDString),
            tracks.contains(where: { $0.id == selectedID })
        {
            selectedTrackID = selectedID
        } else {
            selectedTrackID = tracks.first?.id
        }

        if tracks.count != storedTracks.count {
            persistLibrary()
        }

        refreshDurations(for: tracks)
    }

    private func persistLibrary() {
        let storedTracks = tracks.map { StoredTrack(id: $0.id, path: $0.url.path) }
        if let data = try? JSONEncoder().encode(storedTracks) {
            UserDefaults.standard.set(data, forKey: Keys.storedTracks)
        }

        if let selectedTrackID {
            UserDefaults.standard.set(selectedTrackID.uuidString, forKey: Keys.selectedTrackID)
        } else {
            UserDefaults.standard.removeObject(forKey: Keys.selectedTrackID)
        }
    }

    private func addDefaultAudioIfAvailable() {
        guard let defaultAudioDirectory = Self.defaultAudioDirectories().first(where: { directoryURL in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }) else {
            return
        }

        addURLs([defaultAudioDirectory], autoplayFirst: false)
    }

    private func refreshDurations(for tracks: [ListeningTrack]) {
        for track in tracks {
            Task {
                let loadedDuration = await Self.loadDuration(for: track.url)
                await MainActor.run {
                    self.applyDuration(loadedDuration, to: track.id)
                }
            }
        }
    }

    private func applyDuration(_ loadedDuration: TimeInterval?, to id: ListeningTrack.ID) {
        guard let loadedDuration, let index = tracks.firstIndex(where: { $0.id == id }) else { return }

        tracks[index].duration = loadedDuration
        if selectedTrackID == id {
            duration = loadedDuration
        }
    }

    private static func discoverPlayableMediaURLs(from urls: [URL]) -> [URL] {
        var mediaURLs: [URL] = []
        let fileManager = FileManager.default

        for url in urls {
            guard let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey]) else {
                continue
            }

            if resourceValues.isDirectory == true {
                let keys: [URLResourceKey] = [.isRegularFileKey, .isHiddenKey]
                guard let enumerator = fileManager.enumerator(
                    at: url,
                    includingPropertiesForKeys: keys,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else {
                    continue
                }

                for case let childURL as URL in enumerator {
                    guard
                        let values = try? childURL.resourceValues(forKeys: Set(keys)),
                        values.isRegularFile == true,
                        values.isHidden != true,
                        isPlayableMediaURL(childURL)
                    else {
                        continue
                    }
                    mediaURLs.append(childURL)
                }
            } else if isPlayableMediaURL(url) {
                mediaURLs.append(url)
            }
        }

        return mediaURLs.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    private static func mediaIdentityKey(for url: URL) -> String {
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
        return "\(url.lastPathComponent.lowercased())#\(fileSize)"
    }

    private static func defaultAudioDirectories() -> [URL] {
        var candidates: [URL] = []

        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("DefaultAudio", isDirectory: true))
        }

        var directoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        for _ in 0..<8 {
            candidates.append(directoryURL.appendingPathComponent("备考资料/官方材料/音频", isDirectory: true))
            let parentURL = directoryURL.deletingLastPathComponent()
            if parentURL == directoryURL {
                break
            }
            directoryURL = parentURL
        }

        return candidates
    }

    private static func defaultPlaybackRate() -> Double {
        let storedRate = UserDefaults.standard.double(forKey: Keys.playbackRate)
        return storedRate >= 0.25 ? min(2.0, storedRate) : 1.0
    }

    private static func defaultPlaybackMode() -> PlaybackMode {
        PlaybackMode(rawValue: UserDefaults.standard.string(forKey: Keys.playbackMode) ?? "") ?? .sequence
    }

    private static func defaultBool(_ key: String, fallback: Bool) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return fallback }
        return UserDefaults.standard.bool(forKey: key)
    }

    nonisolated private static func loadDuration(for url: URL) async -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return nil }
        let seconds = duration.seconds
        return seconds.isFinite && seconds > 0 ? seconds : nil
    }
}
