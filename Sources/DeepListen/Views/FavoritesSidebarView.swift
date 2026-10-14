import SwiftUI

struct WorkspaceSidebarView: View {
    @Environment(FavoritesStore.self) private var favorites
    var theme: AppThemeColor
    var searchFocus: FocusState<Bool>.Binding

    var body: some View {
        Group {
            if favorites.workspace == .library {
                SidebarView(theme: theme, searchFocus: searchFocus)
            } else {
                FavoritesSidebarView(searchFocus: searchFocus)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FavoritesSidebarView: View {
    @Environment(FavoritesStore.self) private var favorites
    @Environment(PlayerStore.self) private var player
    var searchFocus: FocusState<Bool>.Binding

    var body: some View {
        @Bindable var favorites = favorites
        VStack(spacing: 0) {
            if favorites.isReviewing {
                HStack {
                    Label("复习中 · 剩余 \(favorites.reviewQueue.count) 句", systemImage: "headphones")
                    Spacer()
                    Button("结束") { favorites.stopReview(); player.pause() }
                }
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
            List(selection: $favorites.selectedID) {
                Section("\(favorites.visiblePassages.count) 条收藏") {
                    ForEach(favorites.visiblePassages) { passage in
                        FavoriteRow(passage: passage, hidesAnswer: favorites.isReviewing && favorites.blindReview)
                            .tag(passage.id)
                            .contextMenu {
                                Button(passage.isMastered ? "放回待复习" : "标记为已掌握") {
                                    favorites.setMastered(!passage.isMastered, for: passage.id)
                                }
                                Button("移除收藏", role: .destructive) { favorites.remove(passage.id) }
                            }
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { favorites.visiblePassages[$0].id }
                        ids.forEach { favorites.remove($0) }
                    }
                }
            }
            .listStyle(.sidebar)
            .disabled(favorites.isReviewing)
            .searchable(text: $favorites.searchText, placement: .sidebar, prompt: "搜索原文、来源或备注")
            .searchFocused(searchFocus)
            .overlay {
                if favorites.visiblePassages.isEmpty {
                    ContentUnavailableView(
                        favorites.passages.isEmpty ? "还没有收藏" : "没有匹配的收藏",
                        systemImage: "star",
                        description: Text(favorites.passages.isEmpty ? "在播放器中点击“收藏本句”即可保存。" : "试试其他关键词。")
                    )
                }
            }
            .onChange(of: favorites.passages) { reconcileSelection() }
            .onChange(of: favorites.searchText) { reconcileSelection() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reconcileSelection() {
        guard !favorites.isReviewing else { return }
        if !favorites.visiblePassages.contains(where: { $0.id == favorites.selectedID }) {
            favorites.selectedID = favorites.visiblePassages.first?.id
        }
    }
}

private struct FavoriteRow: View {
    var passage: SavedPassage
    var hidesAnswer: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(hidesAnswer ? "听力片段" : (passage.text.isEmpty ? "自选片段" : passage.text))
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                Spacer(minLength: 4)
                if passage.isMastered {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.secondary)
                        .accessibilityLabel("已掌握")
                }
            }
            Text(passage.sourceTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            HStack {
                Text(passage.timeLabel).monospacedDigit()
                if !passage.sourceExists { Label("文件缺失", systemImage: "exclamationmark.triangle") }
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}
