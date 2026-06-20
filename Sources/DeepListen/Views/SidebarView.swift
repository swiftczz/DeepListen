import SwiftUI
import AppKit

struct SidebarView: View {
    @Environment(PlayerStore.self) private var player
    @State private var searchText = ""
    @State private var selectedTrackIDs: Set<ListeningTrack.ID> = []
    @State private var anchorIndex: Int?
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
                    Section("听力音频") {
                        if visibleTracks.isEmpty {
                            Text("没有匹配的音频")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 10)
                        }

                        ForEach(visibleTracks, id: \.track.id) { index, track in
                            let isHighlighted = player.selectedTrackID == track.id
                                || selectedTrackIDs.contains(track.id)
                            TrackRow(
                                track: track,
                                index: index + 1,
                                isHighlighted: isHighlighted,
                                theme: theme
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                handleTap(at: index, track: track)
                            }
                            .contextMenu {
                                contextualMenu(for: track)
                            }
                            .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 10))
                            .listRowBackground(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(isHighlighted ? theme.color : Color.clear)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                            )
                        }
                    }
                }
                .listStyle(.sidebar)
                .searchable(text: $searchText, placement: .sidebar, prompt: "搜索音频")
                .onDeleteCommand {
                    performBatchRemove()
                }
            }
        }
    }

    /// 点击处理：遵循 macOS 原生多选语义。
    /// - 无修饰键：清空多选，播放该曲目，记下锚点
    /// - Shift：从锚点到当前项做范围选择，不触发播放
    /// - Cmd：增减单项，不触发播放
    private func handleTap(at index: Int, track: ListeningTrack) {
        let modifiers = NSEvent.modifierFlags
        let trackID = track.id

        if modifiers.contains(.shift), let anchor = anchorIndex {
            let range = min(anchor, index)...max(anchor, index)
            let rangeIDs = visibleTracks[range].map(\.track.id)
            selectedTrackIDs.formUnion(rangeIDs)
        } else if modifiers.contains(.command) {
            if selectedTrackIDs.contains(trackID) {
                selectedTrackIDs.remove(trackID)
            } else {
                selectedTrackIDs.insert(trackID)
            }
            anchorIndex = index
        } else {
            selectedTrackIDs.removeAll()
            player.selectTrack(trackID, autoplay: true)
            anchorIndex = index
        }
    }

    /// 执行批量删除。selection 为空时直接返回。
    private func performBatchRemove() {
        guard !selectedTrackIDs.isEmpty else { return }
        player.removeTracks(selectedTrackIDs)
        selectedTrackIDs.removeAll()
        anchorIndex = nil
    }

    /// 右键菜单：若点击项已在多选集合中，则"移除"作用于整组；否则只删该单项（保持旧行为）。
    @ViewBuilder
    private func contextualMenu(for track: ListeningTrack) -> some View {
        let inSelection = selectedTrackIDs.contains(track.id)
        let removeCount = inSelection ? max(selectedTrackIDs.count, 1) : 1

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
            if inSelection {
                player.removeTracks(selectedTrackIDs)
                selectedTrackIDs.removeAll()
                anchorIndex = nil
            } else {
                player.removeTrack(track.id)
            }
        } label: {
            if removeCount > 1 {
                Label("从列表移除 \(removeCount) 项", systemImage: "minus.circle")
            } else {
                Label("从列表移除", systemImage: "minus.circle")
            }
        }
    }
}

private struct TrackRow: View {
    var track: ListeningTrack
    var index: Int
    var isHighlighted: Bool
    var theme: AppThemeColor

    var body: some View {
        HStack(spacing: 12) {
            Text(String(format: "%02d", index))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(isHighlighted ? theme.selectionForegroundColor : Color.secondary)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            isHighlighted ? Color.white.opacity(0.18) : Color.secondary.opacity(0.10))
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(.body)
                    .fontWeight(.regular)
                    .lineLimit(1)
                    .foregroundStyle(isHighlighted ? theme.selectionForegroundColor : Color.primary)

                HStack(spacing: 6) {
                    Text((track.duration ?? 0).formattedPlaybackTime)
                    Text(track.mediaKind.label)
                }
                .font(.caption2)
                .foregroundStyle(isHighlighted ? theme.selectionForegroundColor.opacity(0.78) : Color.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }
}
