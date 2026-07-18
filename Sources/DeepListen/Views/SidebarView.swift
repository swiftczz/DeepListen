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

    /// Finder 式灰色圆角选中胶囊。
    /// 原生表格的选中高亮（聚焦时为蓝色）由 `SelectionHighlightSuppressor` 关闭，
    /// 因此这里内缩成圆角也不会有蓝色描边从边缘漏出；主题色只保留给「正在播放」。
    @ViewBuilder
    private func rowBackground(isSelected: Bool) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .unemphasizedSelectedContentBackgroundColor))
                .padding(.horizontal, 8)
                .padding(.vertical, 1)
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

    /// 单选切换曲目时保留播放状态：正在播放则继续播放新曲目（与上一首/下一首一致），
    /// 暂停中则静默切换。
    private func selectSingleTrack(_ selection: Set<ListeningTrack.ID>) {
        guard selection.count == 1,
            let trackID = selection.first,
            player.selectedTrackID != trackID
        else {
            return
        }

        player.selectTrack(trackID, autoplay: player.isPlaying)
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
                // 「正在播放」指示用显式 theme.color，文字用不随选中翻转的固定标签色。
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
                    // 中段截断：同一套题的多个 Section 靠尾部编号区分，保住首尾
                    .truncationMode(.middle)

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
        .background(SelectionHighlightSuppressor())
        .accessibilityElement(children: .combine)
        .accessibilityValue(
            isCurrentTrack
                ? (isPlaying ? "正在播放" : "当前音频")
                : ""
        )
    }
}

/// 关闭 SwiftUI sidebar List 底层 NSTableView/NSOutlineView 的原生选中高亮
/// （聚焦时的蓝色强调），让 `listRowBackground` 提供的灰色圆角胶囊成为唯一可见的选中样式。
/// 找不到宿主表格时静默降级（回到原生高亮），不会崩溃。
private struct SelectionHighlightSuppressor: NSViewRepresentable {
    func makeNSView(context: Context) -> ProbeView {
        ProbeView()
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        nsView.suppressEnclosingTableHighlight()
    }

    final class ProbeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            suppressEnclosingTableHighlight()
        }

        func suppressEnclosingTableHighlight() {
            var ancestor = superview
            while let current = ancestor {
                if let tableView = current as? NSTableView {
                    if tableView.selectionHighlightStyle != .none {
                        tableView.selectionHighlightStyle = .none
                    }
                    return
                }
                ancestor = current.superview
            }
        }
    }
}
