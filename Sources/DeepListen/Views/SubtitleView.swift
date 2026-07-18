import SwiftUI

/// 字幕控件行（字幕开关 + 上下文开关）。固定在滚动区上方，不随字幕内容滚动。
struct SubtitleControlsView: View {
    @Environment(PlayerStore.self) private var player

    var theme: AppThemeColor

    var body: some View {
        HStack(spacing: 12) {
            subtitleTitle

            Spacer()

            contextToggle
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

    @ViewBuilder
    private var contextToggle: some View {
        @Bindable var player = player

        if player.showSubtitles, player.subtitleLoadState == .loaded {
            Toggle("上下文", isOn: $player.showSubtitleContext)
                .toggleStyle(.switch)
                .tint(theme.color)
                .help(player.showSubtitleContext ? "只显示当前句" : "显示全文上下文")
                .fixedSize()
        }
    }
}

struct SubtitleView: View {
    @Environment(PlayerStore.self) private var player

    /// 字幕滚动区可视高度（由父视图测量传入），用于单句模式的垂直居中。
    var availableHeight: CGFloat = 0

    var theme: AppThemeColor

    var body: some View {
        Group {
            if !player.showSubtitles {
                subtitleStatus("字幕已隐藏", systemImage: "captions.bubble.slash")
            } else {
                subtitleContent
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: shouldCenterContent ? centeredContentMinHeight : 0,
            alignment: .leading
        )
    }

    /// 上下文（全文列表）保持顶部对齐；单句和状态提示内容矮，
    /// 在剩余可视空间里垂直居中，避免底部大片留白。
    private var shouldCenterContent: Bool {
        !(player.showSubtitles && player.subtitleLoadState == .loaded && player.showSubtitleContext)
    }

    /// 扣除滚动区上下内边距后的估算可用高度，仅影响居中观感，无需精确。
    private var centeredContentMinHeight: CGFloat {
        max(availableHeight - 60, 0)
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
            if player.showSubtitleContext {
                fullTranscriptView
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

    /// 单句模式：句间空隙（无当前句）时预览下一句，
    /// 待其开始播放再原地由灰转主题色，不跳版。
    private var currentSubtitleView: some View {
        Text(player.currentSubtitle?.text ?? player.nextSubtitle?.text ?? " ")
            .font(.title2.weight(.semibold))
            .fontDesign(.rounded)
            .foregroundStyle(player.currentSubtitle == nil ? Color.secondary : theme.color)
            .lineSpacing(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    /// 上下文模式：整篇文稿按"当前句样式"铺开——当前句主题色大字，
    /// 其余句子灰色小字，点击任意句跳转播放。
    private var fullTranscriptView: some View {
        let currentSubtitleID = player.currentSubtitle?.id

        return LazyVStack(alignment: .leading, spacing: 14) {
            ForEach(player.subtitleCues) { cue in
                LyricsRow(
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

/// 歌词式文稿行：沿用"当前句/上下文"的字体层级，悬停提亮提示可点击跳转。
private struct LyricsRow: View {
    var cue: SubtitleCue
    var isCurrent: Bool
    var theme: AppThemeColor
    var onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onTap) {
            Text(cue.text)
                .font(isCurrent ? .title2.weight(.semibold) : .title3)
                .fontDesign(isCurrent ? .rounded : .default)
                .foregroundStyle(foregroundStyle)
                .lineSpacing(isCurrent ? 8 : 4)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("跳转到 \(cue.start.formattedPlaybackTime)")
        .accessibilityLabel("\(cue.start.formattedPlaybackTime)，\(cue.text)")
        .accessibilityValue(isCurrent ? "当前字幕" : "")
        .accessibilityHint("跳转到这一句")
    }

    private var foregroundStyle: Color {
        if isCurrent {
            return theme.color
        }
        return isHovering ? Color.primary : Color.secondary
    }
}
