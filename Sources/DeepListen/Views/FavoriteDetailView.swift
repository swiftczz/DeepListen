import SwiftUI

struct FavoriteDetailView: View {
    @Environment(FavoritesStore.self) private var favorites
    @Environment(PlayerStore.self) private var player
    @State private var showsRelinker = false
    var theme: AppThemeColor

    var body: some View {
        Group {
            if favorites.isReviewComplete {
                ContentUnavailableView {
                    Label("本轮复习完成", systemImage: "checkmark.circle")
                } description: {
                    Text("本轮掌握 \(favorites.reviewedCount) 句，仍有 \(favorites.pendingCount) 句待复习。跳过的句子会留到下次。")
                } actions: {
                    Button("返回收藏") { favorites.stopReview() }
                    Button("继续复习") { beginReview() }.disabled(!favorites.visiblePassages.contains { !$0.isMastered })
                }
            } else if let passage = favorites.selected {
                passageDetail(passage)
            } else {
                ContentUnavailableView("选择一条收藏", systemImage: "star",
                    description: Text("收藏后可以反复听、添加备注，并记录掌握情况。"))
            }
        }
        .fileImporter(isPresented: $showsRelinker, allowedContentTypes: PlayerStore.importableContentTypes) { result in
            switch result {
            case .success(let url):
                guard let id = favorites.selectedID else { return }
                favorites.relink(id, to: url)
                if let passage = favorites.selected { player.loadFavorite(passage) }
            case .failure(let error): player.reportImportFailure(error)
            }
        }
    }

    private func passageDetail(_ passage: SavedPassage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header(passage)
                if !passage.sourceExists {
                    ContentUnavailableView {
                        Label("找不到原媒体文件", systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text("原文和备注仍然保留。重新选择原文件后即可播放。")
                    } actions: {
                        Button("重新关联文件") { showsRelinker = true }
                    }
                } else {
                    FavoriteTransportView(passage: passage, theme: theme)
                    if player.isPreparingMedia {
                        HStack { ProgressView().controlSize(.small); Text("正在准备音频…") }
                    }
                    if let error = player.mediaPreparationError {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                        Button("重试") { player.loadFavorite(passage) }
                    }
                }
                answer(passage)
                    .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
                if !favorites.hidesAnswer {
                    FavoriteNoteEditor(passage: passage).id(passage.id)
                }
                if favorites.isReviewing {
                    reviewActions(passage)
                } else {
                    HStack {
                        Label(passage.isMastered ? "已掌握" : "待复习", systemImage: passage.isMastered ? "checkmark.circle" : "clock")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(passage.isMastered ? "放回待复习" : "标记为已掌握") {
                            favorites.setMastered(!passage.isMastered, for: passage.id)
                        }
                    }
                }
            }
            .frame(maxWidth: 1000)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if favorites.isReviewing {
                    Button("结束复习", systemImage: "stop.circle") { favorites.stopReview(); player.pause() }
                } else {
                    Button("开始复习", systemImage: "headphones") { beginReview() }
                        .disabled(!favorites.visiblePassages.contains { !$0.isMastered })
                }
                Menu {
                    Button("重新关联文件") { showsRelinker = true }
                    Button("移除收藏", role: .destructive) { favorites.remove(passage.id) }
                } label: { Label("收藏操作", systemImage: "ellipsis") }
            }
        }
    }

    private func header(_ passage: SavedPassage) -> some View {
        @Bindable var favorites = favorites
        return VStack(alignment: .leading, spacing: 12) {
            Text(favorites.isReviewing ? "难句复习" : "收藏").font(.largeTitle.weight(.semibold))
            ViewThatFits(in: .horizontal) {
                HStack { sourceLabel(passage); Spacer(); sourceButton(passage) }
                VStack(alignment: .leading, spacing: 10) { sourceLabel(passage); sourceButton(passage) }
            }
            if favorites.isReviewing {
                HStack {
                    Text("剩余 \(favorites.reviewQueue.count) 句").foregroundStyle(.secondary)
                    Spacer()
                    Toggle("先听后看", isOn: $favorites.blindReview).toggleStyle(.switch).fixedSize()
                }
            }
        }
    }

    private func sourceLabel(_ passage: SavedPassage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(passage.sourceTitle).font(.headline).lineLimit(2)
            Text(passage.timeLabel).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private func sourceButton(_ passage: SavedPassage) -> some View {
        Button("回到原文", systemImage: "arrow.uturn.backward") {
            favorites.stopReview()
            favorites.workspace = .library
            player.returnToSource(passage)
        }
        .disabled(!passage.sourceExists)
        .help("回到媒体库并查看这句的上下文")
    }

    @ViewBuilder private func answer(_ passage: SavedPassage) -> some View {
        if favorites.hidesAnswer {
            VStack(alignment: .leading, spacing: 18) {
                Label("先听一听，再看原文", systemImage: "ear").font(.title2.weight(.medium))
                Text("试着听清每个词，或者跟读一遍。原文、译文和备注已隐藏。")
                    .foregroundStyle(.secondary)
                Button("显示原文", systemImage: "eye") { favorites.reveal() }.buttonStyle(.glass)
            }
        } else if passage.text.isEmpty {
            Text("这段音频没有字幕，可以在备注中记录听到的内容。").foregroundStyle(.secondary)
        } else {
            KaraokeSubtitleText(cue: SubtitleCue(index: 0, start: passage.start, end: passage.end,
                text: passage.text, translation: passage.translation), themeColor: theme.color)
                .font(.title.weight(.semibold)).lineSpacing(8).textSelection(.enabled)
        }
    }

    private func reviewActions(_ passage: SavedPassage) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack { repeatButton; Spacer(); skipButton; masteredButton(passage) }
            VStack(alignment: .leading, spacing: 12) { masteredButton(passage); HStack { repeatButton; skipButton } }
        }
    }

    private var repeatButton: some View {
        Button("再练一次", systemImage: "arrow.counterclockwise") {
            favorites.repeatCurrent(); player.replayFavorite()
        }.disabled(favorites.selected?.sourceExists != true)
    }
    private var skipButton: some View {
        Button("暂时跳过") { favorites.advance(mastered: false) }
    }
    private func masteredButton(_ passage: SavedPassage) -> some View {
        Button("听懂了，下一句", systemImage: "checkmark") { favorites.advance(mastered: true) }
            .buttonStyle(.glassProminent)
            .disabled(!passage.sourceExists)
    }
    private func beginReview() { favorites.startReview() }
}

private struct FavoriteTransportView: View {
    @Environment(PlayerStore.self) private var player
    @State private var replayBounce = 0
    var passage: SavedPassage
    var theme: AppThemeColor

    private var isLooping: Bool {
        player.loopStart != nil && player.loopEnd != nil
    }

    var body: some View {
        VStack(spacing: 12) {
            Slider(value: Binding(get: { min(max(player.currentTime, passage.start), passage.end) },
                set: { player.seek(to: $0) }), in: passage.start...passage.end)
                .accessibilityLabel("收藏片段进度")
            ViewThatFits(in: .horizontal) {
                HStack { controls; Spacer(); timeLabel; PlaybackSpeedButton(theme: theme) }
                VStack(alignment: .leading, spacing: 12) {
                    controls
                    HStack { timeLabel; Spacer(); PlaybackSpeedButton(theme: theme) }
                }
            }
        }
        .disabled(player.mediaPreparationError != nil)
    }
    private var controls: some View {
        HStack(spacing: 12) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    PlaybackIconButton(
                        label: player.isPlaying ? "暂停" : "播放",
                        systemImage: player.isPlaying ? "pause.fill" : "play.fill",
                        theme: theme,
                        isProminent: true
                    ) {
                        player.togglePlayPause()
                    }
                    .help(player.isPlaying ? "暂停（空格）" : "播放（空格）")

                    PlaybackIconButton(
                        label: "重听片段",
                        systemImage: "arrow.counterclockwise",
                        theme: theme,
                        isProminent: false,
                        bounceTrigger: replayBounce
                    ) {
                        replayBounce += 1
                        player.replayFavorite()
                    }
                    .help("从收藏片段的开头重新播放")

                    PlaybackIconButton(
                        label: "循环片段",
                        systemImage: "repeat",
                        theme: theme,
                        isProminent: isLooping,
                        isSelected: isLooping
                    ) {
                        player.setFavoriteLooping(!isLooping)
                    }
                    .accessibilityValue(isLooping ? "已开启" : "已关闭")
                    .accessibilityAddTraits(isLooping ? .isSelected : [])
                    .help(isLooping ? "关闭循环：片段播放完后停止" : "开启循环：反复播放当前收藏片段")
                }
            }

            Text(isLooping ? "循环开启" : "循环关闭")
                .font(.caption)
                .foregroundStyle(isLooping ? theme.color : Color.secondary)
                .accessibilityHidden(true)
        }
        .fixedSize()
    }
    private var timeLabel: some View {
        Text("\((player.currentTime - passage.start).formattedPlaybackTime) / \((passage.end - passage.start).formattedPlaybackTime)")
            .font(.callout.monospacedDigit()).foregroundStyle(.secondary).fixedSize()
    }
}

private struct FavoriteNoteEditor: View {
    @Environment(FavoritesStore.self) private var favorites
    var passage: SavedPassage
    @State private var note = ""
    @FocusState private var isEditing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("备注", systemImage: "square.and.pencil")
            TextEditor(text: $note)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 70, maxHeight: 130)
                .padding(10)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                .focused($isEditing)
                .accessibilityLabel("收藏备注")
                .onChange(of: note) { _, value in favorites.updateNote(value, for: passage.id) }
        }
        .onAppear { note = passage.note }
        .focusedSceneValue(\.playbackCommandsEnabled, !isEditing)
    }
}
