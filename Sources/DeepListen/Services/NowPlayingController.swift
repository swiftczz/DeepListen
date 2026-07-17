import MediaPlayer

/// 把播放状态桥接到系统"正在播放"（控制中心、键盘媒体键、AirPods）。
/// 命令回调统一跳回主线程后调用注入的处理闭包，保持 PlayerStore 的 @MainActor 隔离。
@MainActor
final class NowPlayingController {
    struct Handlers: Sendable {
        var play: @MainActor () -> Void
        var pause: @MainActor () -> Void
        var toggle: @MainActor () -> Void
        var next: @MainActor () -> Void
        var previous: @MainActor () -> Void
        var skip: @MainActor (TimeInterval) -> Void
        var seek: @MainActor (TimeInterval) -> Void
    }

    private var didConfigure = false

    func configure(handlers: Handlers) {
        guard !didConfigure else { return }
        didConfigure = true

        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { _ in
            Task { @MainActor in handlers.play() }
            return .success
        }
        center.pauseCommand.addTarget { _ in
            Task { @MainActor in handlers.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { _ in
            Task { @MainActor in handlers.toggle() }
            return .success
        }
        center.nextTrackCommand.addTarget { _ in
            Task { @MainActor in handlers.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { _ in
            Task { @MainActor in handlers.previous() }
            return .success
        }

        center.skipForwardCommand.preferredIntervals = [5]
        center.skipForwardCommand.addTarget { _ in
            Task { @MainActor in handlers.skip(5) }
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [5]
        center.skipBackwardCommand.addTarget { _ in
            Task { @MainActor in handlers.skip(-5) }
            return .success
        }

        center.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let target = event.positionTime
            Task { @MainActor in handlers.seek(target) }
            return .success
        }
    }

    func update(
        title: String,
        isPlaying: Bool,
        currentTime: TimeInterval,
        duration: TimeInterval,
        rate: Double
    ) {
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = title
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        if duration.isFinite, duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = max(currentTime, 0)
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? rate : 0.0

        let infoCenter = MPNowPlayingInfoCenter.default()
        infoCenter.nowPlayingInfo = info
        infoCenter.playbackState = isPlaying ? .playing : .paused
    }

    func clear() {
        let infoCenter = MPNowPlayingInfoCenter.default()
        infoCenter.nowPlayingInfo = nil
        infoCenter.playbackState = .stopped
    }
}
