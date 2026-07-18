import SwiftUI

struct TransportBarView: View {
    @Environment(PlayerStore.self) private var player
    @State private var showsSpeedPopover = false

    var theme: AppThemeColor

    private var timeDisplayText: String {
        guard player.duration.isFinite, player.duration >= 1 else { return "--:-- / --:--" }
        let elapsed = min(max(player.currentTime, 0), player.duration)
        return "\(elapsed.formattedPlaybackTime) / \(player.duration.formattedPlaybackTime)"
    }

    /// 倍速按钮面显示值：整数 "1×"、半档 "1.5×"、四分档 "1.25×"。
    private var speedLabel: String {
        let rate = player.playbackRate
        let number: String
        if rate == rate.rounded() {
            number = String(format: "%.0f", rate)
        } else if (rate * 10).rounded() == rate * 10 {
            number = String(format: "%.1f", rate)
        } else {
            number = String(format: "%.2f", rate)
        }
        return number + "×"
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                timeline
                timeLabel
                playbackControls
            }

            VStack(alignment: .leading, spacing: 12) {
                timeline
                    .frame(maxWidth: .infinity)

                HStack(spacing: 14) {
                    timeLabel
                    Spacer(minLength: 0)
                    playbackControls
                }
            }
        }
    }

    private var timeline: some View {
        ABTimelineSlider(
            value: player.seekTime,
            duration: player.duration,
            loopStart: player.loopStart,
            loopEnd: player.loopEnd,
            theme: theme,
            onSeek: player.seek
        )
        .frame(minWidth: 240)
    }

    private var timeLabel: some View {
        Text(timeDisplayText)
            .monospacedDigit()
            .font(.headline)
            .foregroundStyle(.secondary)
            .fixedSize()
            .help("已播放 / 总时长")
            .accessibilityLabel("播放进度")
            .accessibilityValue(
                player.duration >= 1 ? timeDisplayText : "正在载入时长"
            )
    }

    private var playbackControls: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 14) {
                transportButtons
                playbackOptions
            }
        }
        .fixedSize()
    }

    private var playbackOptions: some View {
        @Bindable var player = player

        return HStack(spacing: 14) {
            IconButton(
                label: "播放模式：\(player.playbackMode.title)",
                systemImage: player.playbackMode.systemImage,
                theme: theme,
                isProminent: false
            ) {
                player.togglePlaybackMode()
            }
            .help("播放模式：\(player.playbackMode.title)")

            GlassButton(
                accessibilityLabel: "倍速",
                theme: theme,
                isProminent: false,
                action: { showsSpeedPopover.toggle() }
            ) {
                Text(speedLabel)
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(player.playbackRate == 1 ? Color.primary : theme.color)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            .help(String(format: "倍速 %.2fx", player.playbackRate))
            .accessibilityValue(String(format: "%.2f 倍", player.playbackRate))
            .popover(isPresented: $showsSpeedPopover, arrowEdge: .bottom) {
                SpeedPopover(
                    rateBinding: $player.playbackRateSelection,
                    rate: player.playbackRate,
                    theme: theme
                )
            }
        }
    }

    private var transportButtons: some View {
        HStack(spacing: 10) {
            IconButton(
                label: player.isPlaying ? "暂停" : "播放",
                systemImage: player.isPlaying ? "pause.fill" : "play.fill",
                theme: theme,
                isProminent: true
            ) {
                player.togglePlayPause()
            }
            .help(player.isPlaying ? "暂停" : "播放")

            IconButton(label: "后退 5 秒", systemImage: "gobackward.5", theme: theme, isProminent: false) {
                player.skip(by: -5)
            }
            .help("后退 5 秒")

            IconButton(label: "前进 5 秒", systemImage: "goforward.5", theme: theme, isProminent: false) {
                player.skip(by: 5)
            }
            .help("前进 5 秒")
        }
    }
}

private struct ABTimelineSlider: View {
    var value: Double
    var duration: TimeInterval
    var loopStart: TimeInterval?
    var loopEnd: TimeInterval?
    var theme: AppThemeColor
    var onSeek: (TimeInterval) -> Void

    @State private var width: CGFloat = 0
    @State private var scrubValue: TimeInterval = 0
    @State private var isScrubbing = false
    @State private var hoverX: CGFloat?

    /// macOS 滑杆滑块中心的活动范围两端各内缩约半个滑块宽，
    /// 时间↔坐标换算按此补偿，A/B 标记与 hover 预览在两端才不偏。
    private let sliderThumbInset: CGFloat = 10

    private var sliderUpperBound: TimeInterval {
        max(duration, 1)
    }

    private var displayedValue: TimeInterval {
        min(max(isScrubbing ? scrubValue : value, 0), sliderUpperBound)
    }

    private var sliderValue: Binding<Double> {
        Binding {
            displayedValue
        } set: { newValue in
            scrubValue = min(max(newValue, 0), sliderUpperBound)
            if !isScrubbing {
                onSeek(scrubValue)
            }
        }
    }

    private var progressAccessibilityValue: String {
        guard duration > 0 else { return "正在载入时长" }
        return "\(displayedValue.formattedPlaybackTime)，共 \(duration.formattedPlaybackTime)"
    }

    var body: some View {
        // .leading 对齐让每个子视图各自垂直居中：滑杆以自然尺寸居中于 46pt 容器，
        // 轨道中心与同高的播放按钮对齐，无需手算 AppKit 滑杆的内部绘制位置。
        ZStack(alignment: .leading) {
            Slider(
                value: sliderValue,
                in: 0...sliderUpperBound,
                onEditingChanged: updateScrubbing
            )
            .tint(theme.color)
            .accessibilityLabel("播放进度")
            .accessibilityValue(progressAccessibilityValue)

            if let loopStart {
                marker(label: "A", time: loopStart)
            }

            if let loopEnd {
                marker(label: "B", time: loopEnd)
            }

            if let loopStart, let loopEnd, loopEnd > loopStart {
                loopRange(start: loopStart, end: loopEnd)
            }

            if let hoverX, duration >= 1 {
                hoverTimePreview(atX: hoverX)
            }
        }
        .frame(height: 46)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { _, newWidth in
            width = newWidth
        }
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let point):
                hoverX = point.x
            case .ended:
                hoverX = nil
            }
        }
    }

    /// 悬停位置的时间气泡，显示在轨道上方；不拦截鼠标事件，拖动滑杆不受影响。
    private func hoverTimePreview(atX x: CGFloat) -> some View {
        let halfBubbleWidth: CGFloat = 26
        return Text(time(atX: x).formattedPlaybackTime)
            .font(.caption.weight(.medium).monospacedDigit())
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.regularMaterial, in: Capsule())
            .offset(
                x: min(max(x - halfBubbleWidth, 0), max(width - halfBubbleWidth * 2, 0)),
                y: -18
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func updateScrubbing(_ editing: Bool) {
        if editing {
            scrubValue = min(max(value, 0), sliderUpperBound)
            isScrubbing = true
        } else {
            let target = scrubValue
            isScrubbing = false
            onSeek(target)
        }
    }

    private func position(for time: TimeInterval) -> CGFloat {
        guard duration > 0, width > sliderThumbInset * 2 else { return 0 }
        let usableWidth = width - sliderThumbInset * 2
        let fraction = min(max(CGFloat(time / duration), 0), 1)
        return sliderThumbInset + fraction * usableWidth
    }

    /// position(for:) 的逆映射：把悬停点 x 坐标换算回时间。
    private func time(atX x: CGFloat) -> TimeInterval {
        guard duration > 0, width > sliderThumbInset * 2 else { return 0 }
        let usableWidth = width - sliderThumbInset * 2
        let fraction = min(max((x - sliderThumbInset) / usableWidth, 0), 1)
        return TimeInterval(fraction) * duration
    }

    private func marker(label: String, time: TimeInterval) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(theme.color)
            Capsule()
                .fill(theme.color)
                .frame(width: 3, height: 14)
        }
        // y 相对垂直中心：整叠上移，使指示胶囊落在轨道上方
        .offset(x: min(max(position(for: time) - 7, 0), max(width - 14, 0)), y: -15)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func loopRange(start: TimeInterval, end: TimeInterval) -> some View {
        let startX = position(for: start)
        let endX = position(for: end)

        // 垂直居中即与轨道同心，无需 y 偏移
        return Capsule()
            .fill(theme.color.opacity(0.28))
            .frame(width: max(endX - startX, 0), height: 5)
            .offset(x: startX)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct SpeedPopover: View {
    var rateBinding: Binding<Double>
    var rate: Double
    var theme: AppThemeColor

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(format: "%.2fx", rate))
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(theme.color)

            Slider(value: rateBinding, in: 0.25...2.0, step: 0.25)
                .tint(theme.color)
                .frame(width: 220)
                .accessibilityLabel("播放速度")
                .accessibilityValue(String(format: "%.2f 倍", rate))

            HStack {
                Text("0.25x")
                Spacer()
                Text("2.00x")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(16)
    }
}

private struct GlassButton<Content: View>: View {
    var accessibilityLabel: String
    var theme: AppThemeColor
    var isProminent: Bool
    var action: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        Button(action: action) {
            content
                .foregroundStyle(isProminent ? theme.selectionForegroundColor : Color.primary)
                .frame(width: 46, height: 46)
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .glassEffect(
                    isProminent
                        ? .regular.tint(theme.color).interactive()
                        : .regular.interactive(),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct IconButton: View {
    var label: String
    var systemImage: String
    var theme: AppThemeColor
    var isProminent: Bool
    var action: () -> Void

    var body: some View {
        GlassButton(
            accessibilityLabel: label,
            theme: theme,
            isProminent: isProminent,
            action: action
        ) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
        }
    }
}
