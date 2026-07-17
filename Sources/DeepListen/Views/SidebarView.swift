import SwiftUI

struct SidebarView: View {
    @Environment(PlayerStore.self) private var player
    @State private var searchText = ""
    @State private var selectedTrackIDs: Set<ListeningTrack.ID> = []

    var theme: AppThemeColor
    var searchFocus: FocusState<Bool>.Binding

    private var visibleTracks: [ListeningTrack] {
        guard !searchText.isEmpty else { return player.tracks }
        return player.tracks.filter {
            $0.title.localizedStandardContains(searchText)
                || $0.url.lastPathComponent.localizedStandardContains(searchText)
        }
    }

    private var displayNumbers: [ListeningTrack.ID: Int] {
        Dictionary(uniqueKeysWithValues: player.tracks.enumerated().map { index, track in
            (track.id, index + 1)
        })
    }

    var body: some View {
        Group {
            if player.tracks.isEmpty {
                ContentUnavailableView(
                    "暂无音频",
                    systemImage: "music.note.list",
                    description: Text(player.isImporting ? "正在导入音频…" : "使用工具栏中的加号添加音视频")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                libraryList
            }
        }
        .onAppear {
            selectCurrentTrackIfNeeded()
        }
        .onChange(of: player.selectedTrackID) { previousTrackID, _ in
            synchronizeSelection(after: previousTrackID)
        }
    }

    private var libraryList: some View {
        List(selection: $selectedTrackIDs) {
            Section("听力音频") {
                if visibleTracks.isEmpty {
                    Text("没有匹配的音频")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 10)
                }

                ForEach(visibleTracks) { track in
                    TrackRow(
                        track: track,
                        displayNumber: displayNumbers[track.id] ?? 0,
                        isCurrentTrack: player.selectedTrackID == track.id,
                        isPlaying: player.selectedTrackID == track.id && player.isPlaying,
                        theme: theme
                    )
                    .tag(track.id)
                    .listRowBackground(rowBackground(isSelected: selectedTrackIDs.contains(track.id)))
                }
                .onMove(perform: moveHandler)
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, placement: .sidebar, prompt: "搜索音频")
        .searchFocused(searchFocus)
        .contextMenu(forSelectionType: ListeningTrack.ID.self) { selection in
            contextualMenu(for: selection)
        } primaryAction: { selection in
            play(selection)
        }
        .onDeleteCommand {
            performBatchRemove()
        }
        .onChange(of: selectedTrackIDs) { _, selection in
            selectSingleTrack(selection)
        }
        .onChange(of: searchText) {
            keepSelectionVisible()
        }
    }

    /// Finder 式灰色选中高亮：用 listRowBackground 替换原生强调色 pill，
    /// 主题色只保留给"正在播放"状态。
    @ViewBuilder
    private func rowBackground(isSelected: Bool) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .unemphasizedSelectedContentBackgroundColor))
                .padding(.horizontal, 10)
        }
    }

    @ViewBuilder
    private func contextualMenu(for selection: Set<ListeningTrack.ID>) -> some View {
        if selection.count == 1,
            let trackID = selection.first,
            let track = player.tracks.first(where: { $0.id == trackID })
        {
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
        }

        if !selection.isEmpty {
            Button(role: .destructive) {
                remove(selection)
            } label: {
                if selection.count > 1 {
                    Label("从列表移除 \(selection.count) 项", systemImage: "minus.circle")
                } else {
                    Label("从列表移除", systemImage: "minus.circle")
                }
            }
        }
    }

    private func play(_ selection: Set<ListeningTrack.ID>) {
        guard selection.count == 1, let trackID = selection.first else { return }
        player.selectTrack(trackID, autoplay: true)
    }

    private func selectSingleTrack(_ selection: Set<ListeningTrack.ID>) {
        guard selection.count == 1,
            let trackID = selection.first,
            player.selectedTrackID != trackID
        else {
            return
        }

        player.selectTrack(trackID, autoplay: false)
    }

    private func keepSelectionVisible() {
        let visibleTrackIDs = Set(visibleTracks.map(\.id))
        selectedTrackIDs.formIntersection(visibleTrackIDs)

        if selectedTrackIDs.isEmpty,
            let selectedTrackID = player.selectedTrackID,
            visibleTrackIDs.contains(selectedTrackID)
        {
            selectedTrackIDs = [selectedTrackID]
        }
    }

    /// 仅在未搜索时启用拖拽排序：此时 visibleTracks 与 player.tracks 顺序一致，偏移量可直接透传。
    /// 搜索过滤时返回 nil 禁用移动，避免过滤后的下标错位。
    private var moveHandler: ((IndexSet, Int) -> Void)? {
        guard searchText.isEmpty else { return nil }
        return { source, destination in
            player.moveTracks(fromOffsets: source, toOffset: destination)
        }
    }

    private func performBatchRemove() {
        remove(selectedTrackIDs)
    }

    private func remove(_ selection: Set<ListeningTrack.ID>) {
        guard !selection.isEmpty else { return }
        player.removeTracks(selection)
        selectedTrackIDs.subtract(selection)
    }

    private func selectCurrentTrackIfNeeded() {
        guard selectedTrackIDs.isEmpty, let selectedTrackID = player.selectedTrackID else { return }
        selectedTrackIDs = [selectedTrackID]
    }

    private func synchronizeSelection(after previousTrackID: ListeningTrack.ID?) {
        let wasFollowingCurrentTrack = selectedTrackIDs.isEmpty
            || previousTrackID.map { selectedTrackIDs == [$0] } == true
        guard wasFollowingCurrentTrack else { return }

        if let selectedTrackID = player.selectedTrackID {
            selectedTrackIDs = [selectedTrackID]
        } else {
            selectedTrackIDs.removeAll()
        }
    }
}

private struct TrackRow: View {
    var track: ListeningTrack
    var displayNumber: Int
    var isCurrentTrack: Bool
    var isPlaying: Bool
    var theme: AppThemeColor

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                // 列表 tint 已被覆盖为灰色（选中 pill 用），
                // "正在播放"指示必须用显式 theme.color，文字用不随选中翻转的固定标签色。
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isCurrentTrack ? theme.color.opacity(0.14) : Color.secondary.opacity(0.10))

                if isCurrentTrack {
                    Image(systemName: isPlaying ? "waveform" : "play.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.color)
                        .accessibilityHidden(true)
                } else {
                    Text(String(format: "%02d", displayNumber))
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                }
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.body)
                    .foregroundStyle(isCurrentTrack ? theme.color : Color(nsColor: .labelColor))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(track.duration?.formattedPlaybackTime ?? "--:--")
                    Text(track.mediaKind.label)
                }
                .font(.caption2)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(
            isCurrentTrack
                ? (isPlaying ? "正在播放" : "当前音频")
                : ""
        )
    }
}
