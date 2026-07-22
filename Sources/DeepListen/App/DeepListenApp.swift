import SwiftUI

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

    var body: some Scene {
        Window("DeepListen", id: "main") {
            ContentView()
                .environment(player)
                .onOpenURL { url in
                    player.openExternalURLs([url])
                }
        }
        .defaultSize(width: 1180, height: 760)
        .windowToolbarStyle(.unified)
        .commands {
            PlaybackCommands(player: player)
        }
    }
}

private struct PlaybackCommands: Commands {
    @FocusedValue(\.playbackCommandsEnabled) private var commandsEnabled

    let player: PlayerStore

    private var allowsCommands: Bool {
        commandsEnabled ?? true
    }

    var body: some Commands {
        CommandMenu("播放") {
            Button("播放/暂停") {
                player.togglePlayPause()
            }
            .disabled(!allowsCommands || player.selectedTrack == nil)

            Button("上一首") {
                player.previousTrack()
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])
            .disabled(!allowsCommands || player.tracks.isEmpty)

            Button("下一首") {
                player.nextTrack()
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
            .disabled(!allowsCommands || player.tracks.isEmpty)

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
            .disabled(!allowsCommands || player.selectedTrack == nil)

            Button("设置 B 点") {
                player.setLoopEnd()
            }
            .keyboardShortcut("b", modifiers: [.command, .option])
            .disabled(!allowsCommands || player.loopStart == nil)

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
