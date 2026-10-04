import SwiftUI
import AppKit

struct PlaybackCommandsEnabledKey: FocusedValueKey {
    typealias Value = Bool
}

extension FocusedValues {
    var playbackCommandsEnabled: Bool? {
        get { self[PlaybackCommandsEnabledKey.self] }
        set { self[PlaybackCommandsEnabledKey.self] = newValue }
    }
}

@main
struct DeepListenApp: App {
    @State private var player = PlayerStore()
    @State private var favorites = FavoritesStore()

    var body: some Scene {
        Window("DeepListen", id: "main") {
            ContentView()
                .environment(player)
                .environment(favorites)
                .onOpenURL { url in
                    favorites.workspace = .library
                    player.openExternalURLs([url])
                }
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unified)
        .commands {
            PlaybackCommands(player: player, favorites: favorites)
        }
    }
}

private struct PlaybackCommands: Commands {
    @FocusedValue(\.playbackCommandsEnabled) private var commandsEnabled

    let player: PlayerStore
    let favorites: FavoritesStore

    private var allowsCommands: Bool {
        let isEditing = (NSApp.keyWindow?.firstResponder as? NSTextView)?.isEditable == true
        let hasFavorite = favorites.workspace != .favorites || (favorites.selected != nil && !favorites.isReviewComplete)
        return (commandsEnabled ?? true) && !isEditing && hasFavorite
    }

    var body: some Commands {
        CommandMenu("收藏") {
            Button("收藏当前句或片段") {
                if let candidate = player.favoriteCandidate { favorites.add(candidate) }
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(!allowsCommands || player.favoriteCandidate == nil)
            Button("收藏") { favorites.workspace = .favorites }
                .keyboardShortcut("2", modifiers: .command)
            Button("媒体库") { favorites.workspace = .library }
                .keyboardShortcut("1", modifiers: .command)
        }
        CommandMenu("播放") {
            Button("播放/暂停") {
                player.togglePlayPause()
            }
            .disabled(!allowsCommands || player.selectedTrack == nil)

            Button("上一句") {
                if favorites.workspace == .favorites {
                    if favorites.isReviewing { favorites.repeatCurrent(); player.replayFavorite() }
                    else { favorites.selectAdjacent(-1) }
                } else { player.jumpToPreviousSubtitle() }
            }
            .disabled(!allowsCommands || player.selectedTrack == nil)

            Button("下一句") {
                if favorites.workspace == .favorites {
                    if favorites.isReviewing { favorites.advance(mastered: false) }
                    else { favorites.selectAdjacent(1) }
                } else { player.jumpToNextSubtitle() }
            }
            .disabled(!allowsCommands || player.selectedTrack == nil)

            Button("上一首") {
                player.previousTrack()
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])
            .disabled(!allowsCommands || player.tracks.isEmpty || player.activeFavorite != nil)

            Button("下一首") {
                player.nextTrack()
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
            .disabled(!allowsCommands || player.tracks.isEmpty || player.activeFavorite != nil)

            Divider()

            Button("后退 5 秒") {
                player.skip(by: -5)
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            .disabled(!allowsCommands || player.selectedTrack == nil)

            Button("前进 5 秒") {
                player.skip(by: 5)
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            .disabled(!allowsCommands || player.selectedTrack == nil)

            Divider()

            Button("设置 A 点") {
                player.setLoopStart()
            }
            .keyboardShortcut("a", modifiers: [.command, .option])
            .disabled(!allowsCommands || player.selectedTrack == nil || player.activeFavorite != nil)

            Button("设置 B 点") {
                player.setLoopEnd()
            }
            .keyboardShortcut("b", modifiers: [.command, .option])
            .disabled(!allowsCommands || player.loopStart == nil || player.activeFavorite != nil)

            Button("清除 A/B 片段") {
                player.clearLoop()
            }
            .keyboardShortcut(.escape, modifiers: [.command, .option])
            .disabled(
                !allowsCommands
                    || (player.loopStart == nil && player.loopEnd == nil)
            )

            Button(player.showSubtitles ? "隐藏字幕" : "显示字幕") {
                player.showSubtitles.toggle()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            .disabled(!allowsCommands)

            Divider()

            Button("切换播放模式") {
                player.togglePlaybackMode()
            }
            .disabled(!allowsCommands)
        }
    }
}
