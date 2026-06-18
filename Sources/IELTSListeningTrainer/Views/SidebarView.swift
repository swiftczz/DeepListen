import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var player: PlayerStore
    @State private var searchText = ""
    var theme: AppThemeColor

    private var visibleTracks: [(index: Int, track: ListeningTrack)] {
        Array(player.tracks.enumerated()).compactMap { index, track in
            guard !searchText.isEmpty else { return (index, track) }
            return track.title.localizedStandardContains(searchText)
                || track.url.lastPathComponent.localizedStandardContains(searchText)
                ? (index, track)
                : nil
        }
    }

    var body: some View {
        Group {
            if player.tracks.isEmpty {
                ContentUnavailableView("暂无音频", systemImage: "music.note.list")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField("搜索音频", text: $searchText)
                                .textFieldStyle(.plain)
                        }
                        .font(.callout)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 10))
                    .listRowBackground(Color.clear)

                    Section("听力音频") {
                        if visibleTracks.isEmpty {
                            Text("没有匹配的音频")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 10)
                        }

                        ForEach(visibleTracks, id: \.track.id) {
                            index, track in
                            TrackRow(
                                track: track,
                                index: index + 1,
                                isSelected: player.selectedTrackID == track.id,
                                theme: theme
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                player.selectTrack(track.id, autoplay: false)
                            }
                            .contextMenu {
                                Button {
                                    player.selectTrack(track.id, autoplay: true)
                                } label: {
                                    Label("播放", systemImage: "play.fill")
                                }

                                Button {
                                    player.revealInFinder(track)
                                } label: {
                                    Label("在访达中显示", systemImage: "finder")
                                }

                                Divider()

                                Button(role: .destructive) {
                                    player.removeTrack(track.id)
                                } label: {
                                    Label("从列表移除", systemImage: "minus.circle")
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 10))
                            .listRowBackground(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(
                                        player.selectedTrackID == track.id
                                            ? theme.color : Color.clear
                                    )
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                            )
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }
}

private struct TrackRow: View {
    var track: ListeningTrack
    var index: Int
    var isSelected: Bool
    var theme: AppThemeColor

    var body: some View {
        HStack(spacing: 12) {
            Text(String(format: "%02d", index))
                .font(.system(.callout, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(isSelected ? theme.selectionForegroundColor : Color.secondary)
                .frame(width: 38, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            isSelected ? Color.white.opacity(0.18) : Color.secondary.opacity(0.10))
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(.body)
                    .fontWeight(.regular)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? theme.selectionForegroundColor : Color.primary)

                HStack(spacing: 6) {
                    Text((track.duration ?? 0).formattedPlaybackTime)
                    Text(track.mediaKind.label)
                }
                .font(.caption2)
                .foregroundStyle(isSelected ? theme.selectionForegroundColor.opacity(0.78) : Color.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }
}
