import SwiftUI

struct PlayerDetailView: View {
    @Environment(PlayerStore.self) private var player
    @State private var detailWidth: CGFloat = 0
    @State private var subtitleAreaHeight: CGFloat = 0
    @State private var autoScrollPaused = false

    var theme: AppThemeColor

    private var horizontalPadding: CGFloat {
        detailWidth < 720 ? 24 : 42
    }

    var body: some View {
        Group {
            if let track = player.selectedTrack {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 24) {
                        PlayerHeaderView(track: track)
                        TransportBarView(theme: theme)
                        ABLoopView(theme: theme)
                        SubtitleControlsView(theme: theme)
                    }
                    .frame(maxWidth: 1120, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 28)
                    .padding(.bottom, 16)

                    ScrollViewReader { scrollProxy in
                        ScrollView {
                            SubtitleView(
                                availableHeight: subtitleAreaHeight,
                                theme: theme
                            )
                            .frame(maxWidth: 1120, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, horizontalPadding)
                            .padding(.top, 8)
                            .padding(.bottom, 24)
                        }
                        .scrollEdgeEffectStyle(.soft, for: .top)
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.height
                        } action: { _, height in
                            subtitleAreaHeight = height
                        }
                        .onScrollPhaseChange { _, newPhase in
                            if newPhase == .interacting {
                                autoScrollPaused = true
                            }
                        }
                        .onChange(of: player.selectedTrackID) {
                            // 换曲目后恢复自动跟随，避免上一曲的手动滚动状态残留
                            autoScrollPaused = false
                        }
                        .onChange(of: player.currentSubtitleIndex) {
                            scrollToCurrentSubtitle(using: scrollProxy)
                        }
                        .onChange(of: player.showSubtitleContext) { _, isOn in
                            guard isOn else { return }
                            autoScrollPaused = false
                            scrollToCurrentSubtitle(using: scrollProxy)
                        }
                        .overlay(alignment: .bottom) {
                            resumeAutoScrollButton(using: scrollProxy)
                        }
                        .animation(.easeOut(duration: 0.2), value: autoScrollPaused)
                    }
                }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { _, width in
                    detailWidth = width
                }
            } else {
                ContentUnavailableView(
                    "暂无听力音频",
                    systemImage: "music.note.list",
                    description: Text("通过 Finder 打开音视频文件后开始练习")
                )
            }
        }
    }

    @ViewBuilder
    private func resumeAutoScrollButton(using proxy: ScrollViewProxy) -> some View {
        if autoScrollPaused,
            player.showSubtitleContext,
            player.showSubtitles,
            player.currentSubtitle != nil
        {
            Button {
                autoScrollPaused = false
                scrollToCurrentSubtitle(using: proxy)
            } label: {
                Label("回到当前句", systemImage: "arrow.down.to.line")
                    .font(.callout.weight(.medium))
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(theme.color)
            .padding(.bottom, 20)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityHint("恢复字幕自动滚动")
        }
    }

    private func scrollToCurrentSubtitle(using proxy: ScrollViewProxy) {
        guard player.showSubtitleContext,
            !autoScrollPaused,
            let currentSubtitleID = player.currentSubtitle?.id
        else {
            return
        }

        withAnimation(.easeInOut(duration: 0.22)) {
            proxy.scrollTo(currentSubtitleID, anchor: .center)
        }
    }
}

private struct PlayerHeaderView: View {
    var track: ListeningTrack

    private var durationText: String {
        guard let duration = track.duration, duration.isFinite, duration >= 1 else {
            return "--:--"
        }
        return duration.formattedPlaybackTime
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(track.title)
                .font(.largeTitle.weight(.semibold))
                .fontDesign(.rounded)
                .lineLimit(2)

            ViewThatFits(in: .horizontal) {
                metadataRow
                metadataColumn
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private var metadataRow: some View {
        HStack(spacing: 18) {
            durationLabel
            mediaLabel
            subtitleLabel
        }
    }

    private var metadataColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            durationLabel
            mediaLabel
            subtitleLabel
        }
    }

    private var durationLabel: some View {
        Label(durationText, systemImage: "clock")
    }

    private var mediaLabel: some View {
        Label("\(track.fileExtension) · \(track.mediaKind.label)", systemImage: "music.note")
    }

    @ViewBuilder
    private var subtitleLabel: some View {
        if let subtitleURL = track.subtitleURL {
            Label(subtitleURL.pathExtension.uppercased(), systemImage: "captions.bubble")
        }
    }
}
