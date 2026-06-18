import SwiftUI

@main
struct IELTSListeningTrainerApp: App {
    @State private var player = PlayerStore()

    var body: some Scene {
        WindowGroup("IELTS Listening Trainer") {
            ContentView()
                .environment(player)
                .onOpenURL { url in
                    player.openExternalURLs([url])
                }
        }
        .defaultSize(width: 1180, height: 760)
        .windowStyle(.hiddenTitleBar)
        .commands {
            PlaybackCommands(player: player)
        }
    }
}

private struct PlaybackCommands: Commands {
    let player: PlayerStore

    var body: some Commands {
        CommandMenu("播放") {
            Button("播放/暂停") {
                player.togglePlayPause()
            }
            .keyboardShortcut(.space, modifiers: [])

            Button("上一首") {
                player.previousTrack()
            }
            .keyboardShortcut("p")

            Button("下一首") {
                player.nextTrack()
            }
            .keyboardShortcut("n")

            Divider()

            Button("后退 5 秒") {
                player.skip(by: -5)
            }
            .keyboardShortcut(.leftArrow, modifiers: [])

            Button("前进 5 秒") {
                player.skip(by: 5)
            }
            .keyboardShortcut(.rightArrow, modifiers: [])

            Divider()

            Button("设置 A 点") {
                player.setLoopStart()
            }
            .keyboardShortcut("a", modifiers: [])

            Button("设置 B 点") {
                player.setLoopEnd()
            }
            .keyboardShortcut("b", modifiers: [])

            Button("清除 A/B 片段") {
                player.clearLoop()
            }
            .keyboardShortcut(.escape, modifiers: [])

            Button("显示/隐藏字幕") {
                player.showSubtitles.toggle()
            }
            .keyboardShortcut("s", modifiers: [])

            Divider()

            Button("切换播放模式") {
                switch player.playbackMode {
                case .sequence:
                    player.playbackMode = .singleLoop
                case .singleLoop:
                    player.playbackMode = .sequence
                }
            }
        }
    }
}
