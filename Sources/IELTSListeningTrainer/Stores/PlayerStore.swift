import AVFoundation
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable final class PlayerStore {
    private(set) var tracks: [ListeningTrack] = []
    var selectedTrackID: ListeningTrack.ID?
    private(set) var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    private(set) var playbackRate: Double = PlayerStore.defaultPlaybackRate()
    var playbackMode: PlaybackMode = PlayerStore.defaultPlaybackMode() {
        didSet {
            UserDefaults.standard.set(playbackMode.rawValue, forKey: Keys.playbackMode)
        }
    }
    var showSubtitles: Bool = PlayerStore.defaultBool(Keys.showSubtitles, fallback: true) {
        didSet {
            UserDefaults.standard.set(showSubtitles, forKey: Keys.showSubtitles)
        }
    }
    var showSubtitleContext: Bool = PlayerStore.defaultBool(
        Keys.showSubtitleContext, fallback: true)
    {
        didSet {
            UserDefaults.standard.set(showSubtitleContext, forKey: Keys.showSubtitleContext)
        }
    }
    private(set) var subtitleCues: [SubtitleCue] = []
    private(set) var currentSubtitleIndex: Int?
    var libraryNotice: String?
    var loopStart: TimeInterval?
    var loopEnd: TimeInterval?

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private let fileRevealer: FileRevealing

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var playbackFinishedTask: Task<Void, Never>?
    @ObservationIgnored private var libraryNoticeTask: Task<Void, Never>?
    @ObservationIgnored private var subtitleLoadTask: Task<Void, Never>?
    @ObservationIgnored private var durationLoadTasks: [ListeningTrack.ID: Task<Void, Never>] = [:]

    private static let playableMediaExtensions = [
        "mp3", "m4a", "aac", "wav", "aiff", "aif", "caf", "flac",
        "mp4", "m4v", "mov", "avi", "mkv",
    ]
    private static let playableMediaExtensionSet = Set(playableMediaExtensions)
    private static let playableMediaContentTypes = playableMediaExtensions.compactMap {
        UTType(filenameExtension: $0)
    }
    static let importableContentTypes = playableMediaContentTypes + [.folder]

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

    init(fileRevealer: FileRevealing = MacFileRevealer()) {
        self.fileRevealer = fileRevealer

        configurePlayer()
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

    isolated deinit {
        playbackFinishedTask?.cancel()
        libraryNoticeTask?.cancel()
        subtitleLoadTask?.cancel()
        durationLoadTasks.values.forEach { $0.cancel() }

        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
    }

    var selectedTrack: ListeningTrack? {
        guard let selectedTrackIndex else { return nil }
        return tracks[selectedTrackIndex]
    }

    var selectedIndex: Int? {
        selectedTrackIndex
    }

    private var selectedTrackIndex: Int? {
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
        case (let start?, let end?) where end > start:
            return "\(start.formattedPlaybackTime) - \(end.formattedPlaybackTime)"
        case (let start?, _):
            return "A \(start.formattedPlaybackTime) 已设置"
        default:
            return "片段未设置"
        }
    }

    var seekTime: TimeInterval {
        get {
            min(currentTime, max(duration, 1))
        }
        set {
            seek(to: newValue)
        }
    }

    var playbackRateSelection: Double {
        get {
            playbackRate
        }
        set {
            setPlaybackRate(newValue)
        }
    }

    @discardableResult
    func addURLs(_ urls: [URL], autoplayFirst: Bool) -> [ListeningTrack] {
        let mediaURLs = Self.discoverPlayableMediaURLs(from: urls)
        guard !mediaURLs.isEmpty else { return [] }

        var firstTargetID: UUID?
        var addedTracks: [ListeningTrack] = []
        var knownMediaIDsByKey = Self.mediaIDsByKey(for: tracks)

        for mediaURL in mediaURLs {
            let mediaKey = Self.mediaIdentityKey(for: mediaURL)

            if let existingTrackID = knownMediaIDsByKey[mediaKey] {
                if firstTargetID == nil {
                    firstTargetID = existingTrackID
                }
                continue
            }

            let track = ListeningTrack(url: mediaURL)
            addedTracks.append(track)
            knownMediaIDsByKey[mediaKey] = track.id
            if firstTargetID == nil {
                firstTargetID = track.id
            }
        }

        guard !addedTracks.isEmpty || firstTargetID != nil else { return [] }

        tracks.append(contentsOf: addedTracks)
        tracks.sort {
            $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent)
                == .orderedAscending
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
        let addedTracks = addURLs(urls, autoplayFirst: true)
        if addedTracks.isEmpty {
            showLibraryNotice("已切换到已存在音频")
        } else if addedTracks.count == 1, let title = addedTracks.first?.title {
            showLibraryNotice("已添加：\(title)")
        } else {
            showLibraryNotice("已添加 \(addedTracks.count) 个音频")
        }
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

    func togglePlaybackMode() {
        switch playbackMode {
        case .sequence:
            playbackMode = .singleLoop
        case .singleLoop:
            playbackMode = .sequence
        }
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
        guard seconds.isFinite else { return }
        let clampedSeconds = duration > 0
            ? min(max(seconds, 0), duration)
            : max(seconds, 0)
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

    func jumpToSubtitle(_ cue: SubtitleCue) {
        seek(to: cue.start)
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
        fileRevealer.revealInFinder(track.url)
    }

    static func isPlayableMediaURL(_ url: URL) -> Bool {
        playableMediaExtensionSet.contains(url.pathExtension.lowercased())
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

        playbackFinishedTask = Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(
                named: .AVPlayerItemDidPlayToEndTime)
            {
                guard let self else { return }
                handlePlaybackFinished(notification)
            }
        }
    }

    private func showLibraryNotice(_ message: String) {
        libraryNoticeTask?.cancel()
        libraryNotice = message

        libraryNoticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled, let self else { return }
            if libraryNotice == message {
                libraryNotice = nil
            }
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
        subtitleLoadTask?.cancel()

        guard let subtitleURL = track.subtitleURL else {
            subtitleCues = []
            currentSubtitleIndex = nil
            return
        }

        subtitleCues = []
        currentSubtitleIndex = nil

        let trackID = track.id
        subtitleLoadTask = Task.detached { [subtitleURL, trackID] in
            let cues = SubtitleParser.parse(url: subtitleURL)
            guard !Task.isCancelled else { return }

            await MainActor.run { [weak self] in
                guard let self, selectedTrackID == trackID else { return }
                subtitleCues = cues
                updateSubtitleIndex(at: currentTime)
                subtitleLoadTask = nil
            }
        }
    }

    private func handlePlaybackTick(_ seconds: TimeInterval) {
        guard seconds.isFinite else { return }

        if let itemDuration = player.currentItem?.duration.seconds, itemDuration.isFinite,
            itemDuration > 0
        {
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
        guard !subtitleCues.isEmpty else {
            currentSubtitleIndex = nil
            return
        }

        if let currentSubtitleIndex, subtitleCues.indices.contains(currentSubtitleIndex) {
            let cue = subtitleCues[currentSubtitleIndex]
            if cue.start <= seconds && seconds <= cue.end {
                return
            }

            let adjacentIndex = seconds > cue.end
                ? currentSubtitleIndex + 1
                : currentSubtitleIndex - 1
            if subtitleCues.indices.contains(adjacentIndex) {
                let adjacentCue = subtitleCues[adjacentIndex]
                if adjacentCue.start <= seconds && seconds <= adjacentCue.end {
                    self.currentSubtitleIndex = adjacentIndex
                    return
                }
            }
        }

        currentSubtitleIndex = subtitleIndex(containing: seconds)
    }

    private func subtitleIndex(containing seconds: TimeInterval) -> Int? {
        var lowerBound = subtitleCues.startIndex
        var upperBound = subtitleCues.endIndex

        while lowerBound < upperBound {
            let middleIndex = lowerBound + (upperBound - lowerBound) / 2
            let cue = subtitleCues[middleIndex]

            if seconds < cue.start {
                upperBound = middleIndex
            } else if seconds > cue.end {
                lowerBound = middleIndex + 1
            } else {
                return middleIndex
            }
        }

        return nil
    }

    private func loadPersistedLibrary() {
        guard
            let data = UserDefaults.standard.data(forKey: Keys.storedTracks),
            let storedTracks = try? JSONDecoder().decode([StoredTrack].self, from: data)
        else {
            return
        }

        tracks = Self.deduplicatedTracks(storedTracks.compactMap { storedTrack in
            let url = URL(filePath: storedTrack.path)
            guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)),
                Self.isPlayableMediaURL(url)
            else {
                return nil
            }
            return ListeningTrack(url: url, id: storedTrack.id)
        })

        if let selectedIDString = UserDefaults.standard.string(forKey: Keys.selectedTrackID),
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
        let storedTracks = tracks.map {
            StoredTrack(id: $0.id, path: $0.url.path(percentEncoded: false))
        }
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
        guard
            let defaultAudioDirectory = Self.defaultAudioDirectories().first(where: {
                Self.isDirectory($0)
            })
        else {
            return
        }

        addURLs([defaultAudioDirectory], autoplayFirst: false)
    }

    private func refreshDurations(for tracks: [ListeningTrack]) {
        for track in tracks {
            let trackID = track.id
            let trackURL = track.url
            durationLoadTasks[trackID]?.cancel()
            durationLoadTasks[trackID] = Task.detached { [trackID, trackURL] in
                let loadedDuration = await Self.loadDuration(for: trackURL)
                guard !Task.isCancelled else { return }

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    applyDuration(loadedDuration, to: trackID)
                    durationLoadTasks[trackID] = nil
                }
            }
        }
    }

    private func applyDuration(_ loadedDuration: TimeInterval?, to id: ListeningTrack.ID) {
        guard let loadedDuration, let index = tracks.firstIndex(where: { $0.id == id }) else {
            return
        }

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
                guard
                    let enumerator = fileManager.enumerator(
                        at: url,
                        includingPropertiesForKeys: keys,
                        options: [.skipsHiddenFiles, .skipsPackageDescendants]
                    )
                else {
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

    private static func mediaIDsByKey(for tracks: [ListeningTrack]) -> [String: ListeningTrack.ID] {
        Dictionary(
            tracks.map { (mediaIdentityKey(for: $0.url), $0.id) },
            uniquingKeysWith: { firstID, _ in firstID }
        )
    }

    private static func deduplicatedTracks(_ tracks: [ListeningTrack]) -> [ListeningTrack] {
        var knownMediaKeys = Set<String>()
        return tracks.filter { track in
            knownMediaKeys.insert(mediaIdentityKey(for: track.url)).inserted
        }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(
            atPath: url.path(percentEncoded: false),
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
    }

    private static func defaultAudioDirectories() -> [URL] {
        var candidates: [URL] = []

        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appending(path: "DefaultAudio", directoryHint: .isDirectory))
        }

        var directoryURL = URL(
            filePath: FileManager.default.currentDirectoryPath, directoryHint: .isDirectory)
        for _ in 0..<8 {
            candidates.append(
                directoryURL.appending(path: "备考资料/官方材料/音频", directoryHint: .isDirectory))
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
        PlaybackMode(rawValue: UserDefaults.standard.string(forKey: Keys.playbackMode) ?? "")
            ?? .sequence
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
