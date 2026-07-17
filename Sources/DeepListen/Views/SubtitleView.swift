import SwiftUI

struct SubtitleView: View {
    @Environment(PlayerStore.self) private var player

    @Binding var displayMode: SubtitleDisplayMode

    var theme: AppThemeColor

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ViewThatFits(in: .horizontal) {
                subtitleControls

                VStack(alignment: .leading, spacing: 12) {
                    subtitleTitle
                    subtitleControlsGroup
                }
            }

            if !player.showSubtitles {
                subtitleStatus("字幕已隐藏", systemImage: "captions.bubble.slash")
            } else {
                subtitleContent
            }
        }
    }

    @ViewBuilder
    private var subtitleContent: some View {
        switch player.subtitleLoadState {
        case .idle, .missing:
            subtitleStatus(
                "未找到与当前媒体同名的 .srt 或 .vtt 字幕",
                systemImage: "captions.bubble"
            )
        case .loading:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
                Text("正在加载字幕…")
            }
            .font(.title3)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 18)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("正在加载字幕")
        case .failed:
            subtitleStatus(
                "字幕文件无法解析，请检查文件格式或编码",
                systemImage: "exclamationmark.triangle"
            )
        case .loaded:
            if displayMode == .transcript {
                transcriptView
            } else {
                currentSubtitleView
            }
        }
    }

    private func subtitleStatus(_ message: String, systemImage: String) -> some View {
        Label(message, systemImage: systemImage)
            .font(.title3)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 18)
    }

    private var currentSubtitleView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if player.showSubtitleContext, let previousSubtitle = player.previousSubtitle {
                Text(previousSubtitle.text)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Text(player.currentSubtitle?.text ?? player.nextSubtitle?.text ?? " ")
                .font(.title2.weight(.semibold))
                .fontDesign(.rounded)
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

    private var subtitleControls: some View {
        HStack(spacing: 12) {
            subtitleTitle

            Spacer()

            subtitleControlsGroup
        }
    }

    private var subtitleTitle: some View {
        @Bindable var player = player

        return Toggle(isOn: $player.showSubtitles) {
            Label("字幕", systemImage: "captions.bubble")
                .labelStyle(.iconOnly)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 20, height: 20)
        }
        .toggleStyle(.button)
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: 10))
        .controlSize(.large)
        .tint(theme.color)
        .help(player.showSubtitles ? "隐藏字幕" : "显示字幕")
        .accessibilityLabel("字幕")
        .accessibilityValue(player.showSubtitles ? "已显示" : "已隐藏")
    }

    private var subtitleControlsGroup: some View {
        @Bindable var player = player

        return HStack(spacing: 12) {
            if player.showSubtitles, player.subtitleLoadState == .loaded {
                Picker("字幕模式", selection: $displayMode) {
                    ForEach(SubtitleDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
                .accessibilityLabel("字幕模式")

                Toggle("上下文", isOn: $player.showSubtitleContext)
                    .toggleStyle(.switch)
                    .tint(theme.color)
                    .disabled(displayMode == .transcript)
                    .help(displayMode == .transcript ? "全文稿模式不显示上下文" : "显示前后字幕")
            }
        }
        .fixedSize()
    }

    private var transcriptView: some View {
        let currentSubtitleID = player.currentSubtitle?.id

        return LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(player.subtitleCues) { cue in
                TranscriptRow(
                    cue: cue,
                    isCurrent: cue.id == currentSubtitleID,
                    theme: theme
                ) {
                    player.jumpToSubtitle(cue)
                }
                .id(cue.id)
            }
        }
        .textSelection(.enabled)
    }
}

private struct TranscriptRow: View {
    var cue: SubtitleCue
    var isCurrent: Bool
    var theme: AppThemeColor
    var onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Text(cue.start.formattedPlaybackTime)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)

                Text(cue.text)
                    .font(.body)
                    .foregroundStyle(isCurrent ? theme.color : Color.primary)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundColor)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("跳转到 \(cue.start.formattedPlaybackTime)")
        .accessibilityLabel("\(cue.start.formattedPlaybackTime)，\(cue.text)")
        .accessibilityValue(isCurrent ? "当前字幕" : "")
        .accessibilityHint("跳转到这一句")
    }

    private var backgroundColor: Color {
        if isCurrent {
            return theme.color.opacity(0.10)
        }
        return isHovering ? Color.secondary.opacity(0.10) : Color.clear
    }
}

enum SubtitleDisplayMode: String, CaseIterable, Identifiable {
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
