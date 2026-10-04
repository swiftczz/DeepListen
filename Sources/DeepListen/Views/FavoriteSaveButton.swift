import SwiftUI

struct FavoriteSaveButton: View {
    @Environment(PlayerStore.self) private var player
    @Environment(FavoritesStore.self) private var favorites

    var body: some View {
        let candidate = player.favoriteCandidate
        let saved = favorites.saved(candidate)
        Button {
            guard let candidate else { return }
            if let saved { favorites.remove(saved.id) }
            else { favorites.add(candidate) }
        } label: {
            Label(saved != nil ? "已收藏" : (candidate?.isClip == true ? "收藏片段" : "收藏本句"),
                systemImage: saved != nil ? "star.fill" : "star")
        }
        .buttonStyle(.glass)
        .disabled(candidate == nil)
        .help(saved != nil ? "取消收藏" : "保存原文与时间范围（⌘D）")
        .accessibilityValue(saved != nil ? "已收藏" : "未收藏")
    }
}
