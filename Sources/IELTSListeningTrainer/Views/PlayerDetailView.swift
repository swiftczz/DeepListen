import SwiftUI

struct PlayerDetailView: View {
    @Environment(PlayerStore.self) private var player
    var theme: AppThemeColor

    var body: some View {
        Group {
            if let track = player.selectedTrack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        HeaderView(track: track, index: (player.selectedIndex ?? 0) + 1, theme: theme)
                        TransportBarView(theme: theme)
                        ABLoopView(theme: theme)
                        SubtitleView(theme: theme)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 42)
                    .padding(.vertical, 42)
                }
                .background(.background)
            } else {
                ContentUnavailableView(
                    "暂无听力音频",
                    systemImage: "music.note.list",
                    description: Text("通过 Finder 打开音视频文件后开始练习")
                )
            }
        }
    }
}

private struct HeaderView: View {
    var track: ListeningTrack
    var index: Int
    var theme: AppThemeColor

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 22) {
            Text(String(format: "%02d", index))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(theme.color)
                .frame(width: 78, alignment: .leading)

            VStack(alignment: .leading, spacing: 12) {
                Text(track.title)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)

                HStack(spacing: 18) {
                    Label((track.duration ?? 0).formattedPlaybackTime, systemImage: "clock")
                    Label("\(track.fileExtension) · \(track.mediaKind.label)", systemImage: "music.note")
                    if track.subtitleURL != nil {
                        Label("SRT", systemImage: "captions.bubble")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct TransportBarView: View {
    @Environment(PlayerStore.self) private var player
    @State private var showsSpeedPopover = false

    var theme: AppThemeColor

    private var remainingTime: TimeInterval {
        max(player.duration - player.currentTime, 0)
    }

    var body: some View {
        @Bindable var player = player

        HStack(spacing: 14) {
            ABTimelineSlider(
                value: $player.seekTime,
                duration: max(player.duration, 1),
                loopStart: player.loopStart,
                loopEnd: player.loopEnd,
                theme: theme
            )
            .frame(minWidth: 240)
            .frame(height: 46)
            .offset(y: 13)

            Text(remainingTime.formattedPlaybackTime)
                .monospacedDigit()
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
                .help("剩余时间")

            IconButton(systemImage: player.playbackMode.systemImage, theme: theme, isProminent: false) {
                player.togglePlaybackMode()
            }
            .help("播放模式：\(player.playbackMode.title)")

            IconButton(systemImage: "speedometer", theme: theme, isProminent: false) {
                showsSpeedPopover.toggle()
            }
            .help(String(format: "倍速 %.2fx", player.playbackRate))
            .popover(isPresented: $showsSpeedPopover, arrowEdge: .bottom) {
                SpeedPopover(rateBinding: $player.playbackRateSelection, rate: player.playbackRate, theme: theme)
            }

            HStack(spacing: 10) {
                IconButton(systemImage: "gobackward.5", theme: theme, isProminent: false) {
                    player.skip(by: -5)
                }
                .help("后退 5 秒")

                IconButton(systemImage: player.isPlaying ? "pause.fill" : "play.fill", theme: theme, isProminent: true) {
                    player.togglePlayPause()
                }
                .help(player.isPlaying ? "暂停" : "播放")

                IconButton(systemImage: "goforward.5", theme: theme, isProminent: false) {
                    player.skip(by: 5)
                }
                .help("前进 5 秒")
            }
            .fixedSize()
        }
    }

}

private struct ABTimelineSlider: View {
    @Binding var value: Double
    var duration: TimeInterval
    var loopStart: TimeInterval?
    var loopEnd: TimeInterval?
    var theme: AppThemeColor

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Slider(value: $value, in: 0...duration)
                    .tint(theme.color)

                if let loopStart {
                    marker(label: "A", time: loopStart, width: proxy.size.width)
                }

                if let loopEnd {
                    marker(label: "B", time: loopEnd, width: proxy.size.width)
                }

                if let loopStart, let loopEnd, loopEnd > loopStart {
                    loopRange(start: loopStart, end: loopEnd, width: proxy.size.width)
                }
            }
        }
    }

    private func position(for time: TimeInterval, width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return min(max(CGFloat(time / duration) * width, 0), width)
    }

    private func marker(label: String, time: TimeInterval, width: CGFloat) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(theme.color)
            Capsule()
                .fill(theme.color)
                .frame(width: 3, height: 14)
        }
        .offset(x: min(max(position(for: time, width: width) - 7, 0), width - 14), y: -3)
        .allowsHitTesting(false)
    }

    private func loopRange(start: TimeInterval, end: TimeInterval, width: CGFloat) -> some View {
        let startX = position(for: start, width: width)
        let endX = position(for: end, width: width)

        return Capsule()
            .fill(theme.color.opacity(0.28))
            .frame(width: max(endX - startX, 0), height: 5)
            .offset(x: startX, y: 22)
            .allowsHitTesting(false)
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

private struct IconButton: View {
    var systemImage: String
    var theme: AppThemeColor
    var isProminent: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isProminent ? theme.selectionForegroundColor : Color.secondary)
                .frame(width: 46, height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isProminent ? theme.color : Color.secondary.opacity(0.10))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct ABLoopView: View {
    @Environment(PlayerStore.self) private var player
    var theme: AppThemeColor

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    loopSummary
                    Spacer()
                    loopButtons
                }

                VStack(alignment: .leading, spacing: 14) {
                    loopSummary
                    loopButtons
                }
            }

            if let loopStart = player.loopStart {
                loopMarkers(loopStart: loopStart)
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var loopSummary: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("A/B 片段练习")
                .font(.callout.weight(.semibold))
            Text(player.loopSummary)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var loopButtons: some View {
        HStack(spacing: 10) {
            Button {
                player.setLoopStart()
            } label: {
                Label("设 A", systemImage: "a.circle")
            }

            Button {
                player.setLoopEnd()
            } label: {
                Label("设 B", systemImage: "b.circle")
            }

            Button {
                player.clearLoop()
            } label: {
                Label("清除", systemImage: "xmark.circle")
            }
            .disabled(player.loopStart == nil && player.loopEnd == nil)
        }
    }

    private func loopMarkers(loopStart: TimeInterval) -> some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(theme.color)
                .frame(width: 22, height: 6)

            Text("A \(loopStart.formattedPlaybackTime)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let loopEnd = player.loopEnd {
                Text("B \(loopEnd.formattedPlaybackTime)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SubtitleView: View {
    @Environment(PlayerStore.self) private var player
    @State private var displayMode: SubtitleDisplayMode = .current
    var theme: AppThemeColor

    var body: some View {
        @Bindable var player = player
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                Label("字幕", systemImage: "captions.bubble")
                    .font(.headline)

                Spacer()

                if player.showSubtitles, !player.subtitleCues.isEmpty {
                    Picker("字幕模式", selection: $displayMode) {
                        ForEach(SubtitleDisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 150)
                }

                Toggle("显示", isOn: $player.showSubtitles)
                    .toggleStyle(.switch)

                Toggle("上下文", isOn: $player.showSubtitleContext)
                    .toggleStyle(.switch)
                    .disabled(!player.showSubtitles || displayMode == .transcript)
            }

            if !player.showSubtitles {
                Text("字幕已隐藏")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
            } else if player.subtitleCues.isEmpty {
                Text("未找到与当前媒体同名的 .srt 字幕")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
            } else if displayMode == .transcript {
                transcriptView
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    if player.showSubtitleContext, let previousSubtitle = player.previousSubtitle {
                        Text(previousSubtitle.text)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    Text(player.currentSubtitle?.text ?? player.nextSubtitle?.text ?? " ")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(player.currentSubtitle == nil ? Color.secondary : theme.color)
                        .lineSpacing(8)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if player.showSubtitleContext, let nextSubtitle = player.nextSubtitle {
                        Text(nextSubtitle.text)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
                .textSelection(.enabled)
            }
        }
    }

    private var transcriptView: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(player.subtitleCues) { cue in
                Button {
                    player.jumpToSubtitle(cue)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Text(cue.start.formattedPlaybackTime)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .leading)

                        Text(cue.text)
                            .font(.body)
                            .foregroundStyle(isCurrent(cue) ? theme.color : Color.primary)
                            .lineLimit(nil)
                            .multilineTextAlignment(.leading)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isCurrent(cue) ? theme.color.opacity(0.10) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .help("跳转到 \(cue.start.formattedPlaybackTime)")
            }
        }
        .textSelection(.enabled)
    }

    private func isCurrent(_ cue: SubtitleCue) -> Bool {
        cue.start <= player.currentTime && player.currentTime <= cue.end
    }
}

private enum SubtitleDisplayMode: String, CaseIterable, Identifiable {
    case current
    case transcript

    var id: String { rawValue }

    var title: String {
        switch self {
        case .current:
            return "当前句"
        case .transcript:
            return "全文稿"
        }
    }
}
