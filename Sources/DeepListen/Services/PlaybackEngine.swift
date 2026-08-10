import AVFoundation
import Foundation

@MainActor
final class PlaybackEngine {
    private static let seekTimescale: CMTimeScale = 1_000_000

    struct Handlers: Sendable {
        var tick: @MainActor @Sendable (TimeInterval) -> Void
        var finished: @MainActor @Sendable () -> Void
    }

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var playbackFinishedTask: Task<Void, Never>?
    private var seekGeneration = 0
    private var isSeekPending = false

    var hasCurrentItem: Bool {
        player.currentItem != nil
    }

    var currentItemDuration: TimeInterval? {
        guard let seconds = player.currentItem?.duration.seconds,
            seconds.isFinite,
            seconds > 0
        else {
            return nil
        }
        return seconds
    }

    init() {
        player.automaticallyWaitsToMinimizeStalling = false
    }

    isolated deinit {
        playbackFinishedTask?.cancel()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
    }

    func configure(handlers: Handlers) {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        playbackFinishedTask?.cancel()

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.08, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            // 观察者已经在主队列上回调，这里只是把这个事实告诉编译器。
            // 若改用 `Task { @MainActor in ... }`，回调会被推迟到下一次调度：
            // 期间发生的 seek（跳转、A/B 回跳、快进快退）会被这个携带旧时间戳的
            // tick 覆盖回去，表现为进度条和字幕闪回一下。顺带省掉每秒约 12 次任务分配。
            MainActor.assumeIsolated {
                guard let self, !self.isSeekPending else { return }
                handlers.tick(time.seconds)
            }
        }

        playbackFinishedTask = Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(
                named: .AVPlayerItemDidPlayToEndTime
            ) {
                guard let self else { return }
                guard let endedItem = notification.object as? AVPlayerItem,
                    endedItem === player.currentItem
                else {
                    continue
                }
                handlers.finished()
            }
        }
    }

    func replaceCurrentItem(with url: URL?) {
        seekGeneration &+= 1
        isSeekPending = false
        let item = url.map(AVPlayerItem.init(url:))
        player.replaceCurrentItem(with: item)
    }

    func play(rate: Double) {
        player.playImmediately(atRate: Float(rate))
    }

    func pause() {
        player.pause()
    }

    func seek(to seconds: TimeInterval) {
        guard seconds.isFinite else { return }

        seekGeneration &+= 1
        let generation = seekGeneration
        isSeekPending = true

        player.seek(
            to: Self.preciseTime(for: seconds),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.seekGeneration == generation else { return }
                self.isSeekPending = false
            }
        }
    }

    func setRate(_ rate: Double) {
        player.rate = Float(rate)
    }

    /// 字幕时间精确到毫秒。显式四舍五入到微秒时间基，避免 Double 转换到
    /// 600 timescale 时向下落入字幕开始点之前（例如 92.040 变成 92.038333）。
    private static func preciseTime(for seconds: TimeInterval) -> CMTime {
        let value = CMTimeValue(
            (seconds * Double(seekTimescale)).rounded()
        )
        return CMTime(value: value, timescale: seekTimescale)
    }
}
