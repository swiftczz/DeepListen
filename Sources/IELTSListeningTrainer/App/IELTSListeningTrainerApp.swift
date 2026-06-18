import AppKit
import SwiftUI

@main
struct IELTSListeningTrainerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var playerStore = PlayerStore()

    var body: some Scene {
        WindowGroup("IELTS Listening Trainer") {
            ContentView()
                .environmentObject(playerStore)
        }
        .defaultSize(width: 1180, height: 760)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("导入文件...") {
                    playerStore.showImportFilesPanel()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("导入目录...") {
                    playerStore.showImportFolderPanel()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Divider()

                Button("清空列表", role: .destructive) {
                    playerStore.clearLibrary()
                }
            }

            CommandMenu("播放") {
                Button(playerStore.isPlaying ? "暂停" : "播放") {
                    playerStore.togglePlayPause()
                }
                .keyboardShortcut(.space, modifiers: [])

                Button("上一首") {
                    playerStore.previousTrack()
                }
                .keyboardShortcut("p", modifiers: [.command])

                Button("下一首") {
                    playerStore.nextTrack()
                }
                .keyboardShortcut("n", modifiers: [.command])

                Divider()

                Picker("播放模式", selection: $playerStore.playbackMode) {
                    ForEach(PlaybackMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(playerStore)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        OpenFileCoordinator.shared.receive(urls)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        OpenFileCoordinator.shared.receive([URL(fileURLWithPath: filename)])
        return true
    }
}
