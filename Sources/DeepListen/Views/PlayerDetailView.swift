import SwiftUI

struct PlayerDetailView: View {
    @Environment(PlayerStore.self) private var player
    @State private var detailWidth: CGFloat = 0
    @State private var subtitleDisplayMode: SubtitleDisplayMode = .current

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
                    }
                    .frame(maxWidth: 1120, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 28)
                    .padding(.bottom, 24)

                    ScrollViewReader { scrollProxy in
                        ScrollView {
                            SubtitleView(
                                displayMode: $subtitleDisplayMode,
                                theme: theme
                            )
                            .frame(maxWidth: 1120, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, horizontalPadding)
                            .padding(.vertical, 24)
                        }
                        .scrollEdgeEffectStyle(.soft, for: .top)
                        .onChange(of: player.currentSubtitleIndex) {
                            scrollToCurrentSubtitle(using: scrollProxy)
                        }
                        .onChange(of: subtitleDisplayMode) { _, newMode in
                            guard newMode == .transcript else { return }
                            scrollToCurrentSubtitle(using: scrollProxy)
                        }
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

    private func scrollToCurrentSubtitle(using proxy: ScrollViewProxy) {
        guard subtitleDisplayMode == .transcript,
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
