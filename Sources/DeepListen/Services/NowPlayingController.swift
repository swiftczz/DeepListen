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
    /// MPRemoteCommandCenter 是全局单例，注册的 target 必须自己持有句柄才能摘除。
    private var registeredTargets: [(command: MPRemoteCommand, target: Any)] = []

    isolated deinit {
        teardown()
    }

    func configure(handlers: Handlers) {
        guard !didConfigure else { return }
        didConfigure = true

        let center = MPRemoteCommandCenter.shared()

        register(center.playCommand) { _ in
            Task { @MainActor in handlers.play() }
            return .success
        }
        register(center.pauseCommand) { _ in
            Task { @MainActor in handlers.pause() }
            return .success
        }
        register(center.togglePlayPauseCommand) { _ in
            Task { @MainActor in handlers.toggle() }
            return .success
        }
        register(center.nextTrackCommand) { _ in
            Task { @MainActor in handlers.next() }
            return .success
        }
        register(center.previousTrackCommand) { _ in
            Task { @MainActor in handlers.previous() }
            return .success
        }

        center.skipForwardCommand.preferredIntervals = [5]
        register(center.skipForwardCommand) { _ in
            Task { @MainActor in handlers.skip(5) }
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [5]
        register(center.skipBackwardCommand) { _ in
            Task { @MainActor in handlers.skip(-5) }
            return .success
        }

        register(center.changePlaybackPositionCommand) { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let target = event.positionTime
            Task { @MainActor in handlers.seek(target) }
            return .success
        }
    }

    /// 摘除全部远程命令并清空"正在播放"信息，让出系统媒体键控制权。
    func teardown() {
        for entry in registeredTargets {
            entry.command.removeTarget(entry.target)
        }
        registeredTargets.removeAll()
        didConfigure = false

        let infoCenter = MPNowPlayingInfoCenter.default()
        infoCenter.nowPlayingInfo = nil
        infoCenter.playbackState = .stopped
    }

    private func register(
        _ command: MPRemoteCommand,
        handler: @escaping @Sendable (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
    ) {
        let target = command.addTarget(handler: handler)
        registeredTargets.append((command: command, target: target))
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
