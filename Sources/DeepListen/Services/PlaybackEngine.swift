import AVFoundation
import Foundation

@MainActor
final class PlaybackEngine {
    struct Handlers: Sendable {
        var tick: @MainActor @Sendable (TimeInterval) -> Void
        var finished: @MainActor @Sendable () -> Void
    }

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var playbackFinishedTask: Task<Void, Never>?

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
        ) { time in
            Task { @MainActor in
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
        player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    func setRate(_ rate: Double) {
        player.rate = Float(rate)
    }
}
