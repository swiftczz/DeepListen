import Foundation
import Observation

@MainActor
@Observable final class PlayerStore {
    private(set) var tracks: [ListeningTrack] = []
    var selectedTrackID: ListeningTrack.ID?
    private(set) var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    private(set) var playbackRate: Double
    var playbackMode: PlaybackMode {
        didSet {
            persistence.savePlaybackMode(playbackMode)
        }
    }
    var showSubtitles: Bool {
        didSet {
            persistence.saveShowSubtitles(showSubtitles)
        }
    }
    var showSubtitleContext: Bool {
        didSet {
            persistence.saveShowSubtitleContext(showSubtitleContext)
        }
    }
    private(set) var isImporting = false
    var libraryNotice: LibraryNotice?
    var loopStart: TimeInterval?
    var loopEnd: TimeInterval?
    private(set) var isSubtitleLooping = false
    private(set) var playbackFeedback: PlaybackFeedback?

    @ObservationIgnored private let playbackEngine = PlaybackEngine()
    @ObservationIgnored private let subtitleSession = SubtitleSession()
    @ObservationIgnored private let persistence: PlayerPersistence
    @ObservationIgnored private let fileRevealer: FileRevealing
    @ObservationIgnored private let nowPlayingController = NowPlayingController()

    @ObservationIgnored private var libraryNoticeTask: Task<Void, Never>?
    @ObservationIgnored private var subtitleLoadTask: Task<Void, Never>?
    @ObservationIgnored private var importTask: Task<Void, Never>?
    @ObservationIgnored private var playbackPositionSaveTask: Task<Void, Never>?
    @ObservationIgnored private var playbackFeedbackTask: Task<Void, Never>?
    @ObservationIgnored private var durationLoadTasks: [ListeningTrack.ID: Task<Void, Never>] = [:]

    static let importableContentTypes = MediaDiscoveryService.importableContentTypes

    init(fileRevealer: FileRevealing = MacFileRevealer()) {
        let persistence = PlayerPersistence()
        self.persistence = persistence
        self.fileRevealer = fileRevealer
        playbackRate = persistence.playbackRate
        playbackMode = persistence.playbackMode
        showSubtitles = persistence.showSubtitles
        showSubtitleContext = persistence.showSubtitleContext

        configurePlaybackEngine()
        configureNowPlaying()
        loadPersistedLibrary()

        if selectedTrackID == nil {
            selectedTrackID = tracks.first?.id
        }

        if selectedTrackID != nil {
            loadCurrentTrack(autoplay: false, restoresSavedPosition: true)
        }
    }

    isolated deinit {
        libraryNoticeTask?.cancel()
        subtitleLoadTask?.cancel()
        importTask?.cancel()
        playbackPositionSaveTask?.cancel()
        playbackFeedbackTask?.cancel()
        durationLoadTasks.values.forEach { $0.cancel() }
        nowPlayingController.teardown()
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

    var subtitleCues: [SubtitleCue] {
        subtitleSession.cues
    }

    var subtitleLoadState: SubtitleLoadState {
        subtitleSession.loadState
    }

    var currentSubtitleIndex: Int? {
        subtitleSession.currentIndex
    }

    var currentSubtitle: SubtitleCue? {
        subtitleSession.currentCue
    }

    var displayedSubtitleIndex: Int? {
        subtitleSession.displayedIndex
    }

    var displayedSubtitle: SubtitleCue? {
        subtitleSession.displayedCue
    }

    /// 字幕之间存在空档时继续沿用上一句，直到下一句真正开始。
    /// 第一条字幕开始前没有上一句，因此仍返回 nil。
    var subtitleForSentenceLoop: SubtitleCue? {
        subtitleSession.sentenceLoopCue
    }

    var nextSubtitle: SubtitleCue? {
        subtitleSession.nextCue
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

    func openExternalURLs(_ urls: [URL]) {
        startImport(urls, autoplayFirst: true, announcesResult: true)
    }

    func reportImportFailure(_ error: Error) {
        showLibraryNotice(
            "导入失败：\(error.localizedDescription)",
            kind: .failure
        )
    }

    private func startImport(
        _ urls: [URL],
        autoplayFirst: Bool,
        announcesResult: Bool
    ) {
        guard !urls.isEmpty else { return }
        guard !isImporting else {
            if announcesResult {
                showLibraryNotice("正在导入，请稍候", kind: .warning)
            }
            return
        }

        isImporting = true
        let existingTracks = tracks

        importTask = Task { [weak self, urls, existingTracks] in
            let discoveryTask = Task.detached(priority: .userInitiated) {
                MediaDiscoveryService.discover(
                    from: urls,
                    existingTracks: existingTracks
                )
            }

            let result = await withTaskCancellationHandler {
                await discoveryTask.value
            } onCancel: {
                discoveryTask.cancel()
            }

            guard let self else { return }
            defer {
                isImporting = false
                importTask = nil
            }
            guard !Task.isCancelled else { return }

            applyImportResult(result, autoplayFirst: autoplayFirst)
            if announcesResult {
                announceImportResult(result)
            }
        }
    }

    private func applyImportResult(
        _ result: MediaDiscoveryResult,
        autoplayFirst: Bool
    ) {
        guard result.playableCount > 0 else { return }

        // 仅对新增批次按文件名排序后追加，保留用户手动调整过的既有顺序。
        let sortedAddedTracks = result.addedTracks.sorted {
            $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent)
                == .orderedAscending
        }
        tracks.append(contentsOf: sortedAddedTracks)
        refreshDurations(for: sortedAddedTracks)

        if selectedTrackID == nil, let firstTrack = tracks.first {
            selectTrack(firstTrack.id, autoplay: false)
        }

        if autoplayFirst, let firstTargetID = result.firstTargetID {
            selectTrack(firstTargetID, autoplay: true)
        }

        persistLibrary()
    }

    private func announceImportResult(_ result: MediaDiscoveryResult) {
        if result.playableCount == 0 {
            showLibraryNotice("未找到可导入的音视频", kind: .warning)
        } else if result.addedTracks.isEmpty {
            showLibraryNotice("已切换到列表中的音频", kind: .success)
        } else if result.addedTracks.count == 1, let title = result.addedTracks.first?.title {
            showLibraryNotice("已添加：\(title)", kind: .success)
        } else {
            showLibraryNotice("已添加 \(result.addedTracks.count) 个音频", kind: .success)
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

        savePlaybackPosition()
        selectedTrackID = id
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
        showPlaybackFeedback(.playbackMode(playbackMode))
    }

    func play() {
        if !playbackEngine.hasCurrentItem {
            if selectedTrackID == nil {
                selectedTrackID = tracks.first?.id
            }
            loadCurrentTrack(autoplay: false)
        }

        guard playbackEngine.hasCurrentItem else { return }

        if duration > 0, currentTime >= duration {
            seek(to: 0)
        }

        isPlaying = true
        playbackEngine.play(rate: playbackRate)
        updateNowPlaying()
    }

    func pause() {
        playbackEngine.pause()
        isPlaying = false
        savePlaybackPosition()
        updateNowPlaying()
    }

    /// 手动切换到下一首会在末尾回绕到第一首（显式操作，回绕是用户预期）。
    /// 这与顺序播放放完最后一首后停止（见 handlePlaybackFinished）是有意区分的：
    /// 自动连播不应无限循环整个列表。
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
        seek(to: seconds, savesPlaybackPosition: true)
    }

    private func seek(
        to seconds: TimeInterval,
        savesPlaybackPosition: Bool
    ) {
        guard seconds.isFinite else { return }
        let clampedSeconds = duration > 0
            ? min(max(seconds, 0), duration)
            : max(seconds, 0)
        currentTime = clampedSeconds
        subtitleSession.updatePosition(at: clampedSeconds)
        playbackEngine.seek(to: clampedSeconds)
        if savesPlaybackPosition {
            schedulePlaybackPositionSave()
        }
        updateNowPlaying()
    }

    /// 由应用生命周期调用，立即保存当前曲目和播放位置。
    func savePlaybackPosition() {
        playbackPositionSaveTask?.cancel()
        playbackPositionSaveTask = nil
        guard let selectedTrackID else { return }
        persistence.savePlaybackPosition(currentTime, for: selectedTrackID)
    }

    func skip(by seconds: TimeInterval) {
        seek(to: currentTime + seconds)
        if isPlaying {
            playbackEngine.play(rate: playbackRate)
        }
        showPlaybackFeedback(.skip(seconds: Int(seconds.rounded())))
    }

    func jumpToSubtitle(_ cue: SubtitleCue) {
        if isSubtitleLooping {
            setSubtitleLoopRange(cue)
        }

        seek(to: cue.start)
        if isPlaying {
            playbackEngine.play(rate: playbackRate)
        }
    }

    /// 使用当前字幕的起止时间设置 A/B 循环。开启后点击其他字幕句时，
    /// `jumpToSubtitle(_:)` 会让循环范围跟随新句子。
    func setSubtitleLooping(_ enabled: Bool) {
        guard enabled else {
            clearLoop()
            return
        }
        guard let currentSubtitle = subtitleForSentenceLoop else { return }

        isSubtitleLooping = true
        setSubtitleLoopRange(currentSubtitle)
        jumpToSubtitle(currentSubtitle)
    }

    func setPlaybackRate(_ rate: Double) {
        let stepped = (rate / 0.25).rounded() * 0.25
        let clamped = min(2.0, max(0.25, stepped))
        playbackRate = clamped
        persistence.savePlaybackRate(clamped)

        if isPlaying {
            playbackEngine.setRate(clamped)
        }
        showPlaybackFeedback(.playbackRate(clamped))
        updateNowPlaying()
    }

    func setLoopStart() {
        isSubtitleLooping = false
        loopStart = currentTime
        if let loopEnd, loopEnd <= currentTime {
            self.loopEnd = nil
        }
    }

    func setLoopEnd() {
        guard let loopStart else { return }
        isSubtitleLooping = false

        if currentTime > loopStart {
            loopEnd = currentTime
        }
    }

    func clearLoop() {
        loopStart = nil
        loopEnd = nil
        isSubtitleLooping = false
    }

    private func setSubtitleLoopRange(_ cue: SubtitleCue) {
        loopStart = cue.start
        loopEnd = cue.end
    }

    /// 拖拽排序：移动曲目并持久化手动顺序。仅在未过滤（完整列表）时调用。
    func moveTracks(fromOffsets source: IndexSet, toOffset destination: Int) {
        tracks.move(fromOffsets: source, toOffset: destination)
        persistLibrary()
    }

    func removeTrack(_ id: ListeningTrack.ID) {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        let removedSelectedTrack = tracks[index].id == selectedTrackID
        cancelDurationLoads(for: [id])
        tracks.remove(at: index)

        if removedSelectedTrack {
            pause()
            playbackEngine.replaceCurrentItem(with: nil)
            selectedTrackID = tracks.indices.contains(index) ? tracks[index].id : tracks.first?.id
            loadCurrentTrack(autoplay: false)
        }

        persistLibrary()
    }

    /// 批量移除多个音频。若当前播放曲目在被删集合中，暂停并切到剩余列表的首项
    /// （批量删除后"相邻曲目"概念模糊，首项更稳健）；否则保持播放不变。
    func removeTracks(_ ids: Set<ListeningTrack.ID>) {
        guard !ids.isEmpty else { return }

        let removedSelectedTrack = selectedTrackID.map { ids.contains($0) } ?? false
        cancelDurationLoads(for: ids)
        tracks.removeAll { ids.contains($0.id) }

        if removedSelectedTrack {
            pause()
            playbackEngine.replaceCurrentItem(with: nil)
            selectedTrackID = tracks.first?.id
            loadCurrentTrack(autoplay: false)
        }

        persistLibrary()
    }

    func clearLibrary() {
        importTask?.cancel()
        importTask = nil
        isImporting = false
        subtitleLoadTask?.cancel()
        subtitleLoadTask = nil
        cancelDurationLoads(for: tracks.map(\.id))
        pause()
        playbackEngine.replaceCurrentItem(with: nil)
        tracks.removeAll()
        selectedTrackID = nil
        subtitleSession.reset()
        currentTime = 0
        duration = 0
        clearLoop()
        persistLibrary()
    }

    func revealInFinder(_ track: ListeningTrack) {
        fileRevealer.revealInFinder(track.url)
    }

    static func isPlayableMediaURL(_ url: URL) -> Bool {
        MediaDiscoveryService.isPlayableMediaURL(url)
    }

    private func configurePlaybackEngine() {
        playbackEngine.configure(
            handlers: PlaybackEngine.Handlers(
                tick: { [weak self] seconds in self?.handlePlaybackTick(seconds) },
                finished: { [weak self] in self?.handlePlaybackFinished() }
            )
        )
    }

    private func configureNowPlaying() {
        nowPlayingController.configure(
            handlers: NowPlayingController.Handlers(
                play: { [weak self] in self?.play() },
                pause: { [weak self] in self?.pause() },
                toggle: { [weak self] in self?.togglePlayPause() },
                next: { [weak self] in self?.nextTrack() },
                previous: { [weak self] in self?.previousTrack() },
                skip: { [weak self] seconds in self?.skip(by: seconds) },
                seek: { [weak self] target in self?.seek(to: target) }
            )
        )
    }

    private func updateNowPlaying() {
        guard let selectedTrack else {
            nowPlayingController.clear()
            return
        }

        nowPlayingController.update(
            title: selectedTrack.title,
            isPlaying: isPlaying,
            currentTime: currentTime,
            duration: duration,
            rate: playbackRate
        )
    }

    private func showLibraryNotice(_ message: String, kind: LibraryNotice.Kind) {
        libraryNoticeTask?.cancel()
        let notice = LibraryNotice(message: message, kind: kind)
        libraryNotice = notice

        libraryNoticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled, let self else { return }
            if libraryNotice == notice {
                libraryNotice = nil
            }
        }
    }

    private func loadCurrentTrack(
        autoplay: Bool,
        restoresSavedPosition: Bool = false
    ) {
        guard let index = selectedTrackIndex else {
            playbackEngine.pause()
            isPlaying = false
            playbackEngine.replaceCurrentItem(with: nil)
            subtitleSession.reset()
            currentTime = 0
            duration = 0
            clearLoop()
            nowPlayingController.clear()
            return
        }

        // 每次载入都重新匹配同名字幕：曲目导入后才补上的 .srt/.vtt/.lrc 也能被发现，
        // 否则 subtitleURL 只在 init 时解析一次，必须重启才生效。
        let resolvedSubtitleURL = ListeningTrack.matchingSubtitleURL(for: tracks[index].url)
        if tracks[index].subtitleURL != resolvedSubtitleURL {
            tracks[index].subtitleURL = resolvedSubtitleURL
        }
        let selectedTrack = tracks[index]

        // 必须先暂停：replaceCurrentItem 不会停下正在播放的 AVPlayer，
        // 新曲目会带着原速率直接开播，而 isPlaying 已被置 false，声音与按钮状态脱节。
        playbackEngine.pause()
        playbackEngine.replaceCurrentItem(with: selectedTrack.url)
        isPlaying = false
        duration = selectedTrack.duration ?? 0
        currentTime = restoresSavedPosition
            ? restoredPlaybackPosition(for: selectedTrack)
            : 0
        playbackEngine.seek(to: currentTime)
        clearLoop()
        loadSubtitles(for: selectedTrack)

        refreshDurations(for: [selectedTrack])
        updateNowPlaying()

        if autoplay {
            play()
        }
    }

    private func loadSubtitles(for track: ListeningTrack) {
        subtitleLoadTask?.cancel()

        guard let subtitleURL = track.subtitleURL else {
            subtitleSession.markMissing()
            return
        }

        subtitleSession.beginLoading()

        let trackID = track.id
        let mediaDuration = track.duration ?? duration
        subtitleLoadTask = Task.detached { [subtitleURL, trackID, mediaDuration] in
            let cues = SubtitleParser.parse(url: subtitleURL, mediaDuration: mediaDuration)
            guard !Task.isCancelled else { return }

            await MainActor.run { [weak self] in
                guard let self, selectedTrackID == trackID else { return }
                subtitleSession.apply(cues, at: currentTime)
                subtitleLoadTask = nil
            }
        }
    }

    private func handlePlaybackTick(_ seconds: TimeInterval) {
        guard seconds.isFinite else { return }

        if let itemDuration = playbackEngine.currentItemDuration,
            duration != itemDuration
        {
            // @Observable 的写入不做相等性去重，不加判断会每 80ms 触发一次无谓的视图失效。
            duration = itemDuration
        }

        currentTime = seconds
        subtitleSession.updatePosition(at: seconds)

        if let loopStart, let loopEnd, loopEnd > loopStart, seconds >= loopEnd {
            seek(to: loopStart, savesPlaybackPosition: false)
            if isPlaying {
                playbackEngine.play(rate: playbackRate)
            }
        }
    }

    private func handlePlaybackFinished() {
        if let loopStart, let loopEnd, loopEnd > loopStart {
            seek(to: loopStart, savesPlaybackPosition: false)
            play()
            return
        }

        switch playbackMode {
        case .singleLoop:
            seek(to: 0, savesPlaybackPosition: false)
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

    private func loadPersistedLibrary() {
        let library = persistence.loadLibrary()
        tracks = library.tracks
        selectedTrackID = library.selectedTrackID

        if library.needsRewrite {
            persistLibrary()
        }

        refreshDurations(for: tracks)
    }

    private func persistLibrary() {
        persistence.saveLibrary(tracks: tracks, selectedTrackID: selectedTrackID)
    }

    private func restoredPlaybackPosition(for track: ListeningTrack) -> TimeInterval {
        let storedPosition = persistence.playbackPosition(for: track.id)
        guard storedPosition > 0 else { return 0 }

        guard let duration = track.duration, duration > 0 else {
            return storedPosition
        }

        // 已经播放到结尾的曲目下次从头开始。
        guard storedPosition < duration - 0.5 else { return 0 }
        return min(storedPosition, duration)
    }

    private func schedulePlaybackPositionSave() {
        playbackPositionSaveTask?.cancel()
        guard let trackID = selectedTrackID else { return }
        let position = currentTime

        playbackPositionSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self, selectedTrackID == trackID else { return }
            persistence.savePlaybackPosition(position, for: trackID)
            playbackPositionSaveTask = nil
        }
    }

    private func showPlaybackFeedback(_ kind: PlaybackFeedback.Kind) {
        playbackFeedbackTask?.cancel()
        let feedback = PlaybackFeedback(kind: kind)
        playbackFeedback = feedback

        playbackFeedbackTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(850))
            guard !Task.isCancelled, let self else { return }
            if playbackFeedback == feedback {
                playbackFeedback = nil
            }
            playbackFeedbackTask = nil
        }
    }

    /// 只解析尚未缓存时长的曲目。已缓存时重复解析不仅白建一次 AVURLAsset，
    /// 还会在批次排空时多触发一次全库落盘——切歌路径每次都会走到这里。
    private func refreshDurations(for tracks: [ListeningTrack]) {
        for track in tracks where track.duration == nil {
            let trackID = track.id
            let trackURL = track.url
            durationLoadTasks[trackID]?.cancel()
            durationLoadTasks[trackID] = Task.detached { [trackID, trackURL] in
                let loadedDuration = await MediaDurationLoader.loadDuration(for: trackURL)
                guard !Task.isCancelled else { return }

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    applyDuration(loadedDuration, to: trackID)
                    durationLoadTasks[trackID] = nil
                    // 整批加载完再落盘一次，避免每个曲目都重写一遍整个列表。
                    if durationLoadTasks.isEmpty {
                        persistLibrary()
                    }
                }
            }
        }
    }

    /// 曲目被移除时取消其在途的时长解析任务，避免做无用功。
    private func cancelDurationLoads(for ids: some Sequence<ListeningTrack.ID>) {
        for id in ids {
            durationLoadTasks[id]?.cancel()
            durationLoadTasks[id] = nil
        }
    }

    private func applyDuration(_ loadedDuration: TimeInterval?, to id: ListeningTrack.ID) {
        guard let loadedDuration, let index = tracks.firstIndex(where: { $0.id == id }) else {
            return
        }

        // 同 handlePlaybackTick：@Observable 的写入不做相等性去重，
        // 写入同值会白白让整个曲目列表失效。
        if tracks[index].duration != loadedDuration {
            tracks[index].duration = loadedDuration
        }
        if selectedTrackID == id, duration != loadedDuration {
            duration = loadedDuration
        }
    }

}
