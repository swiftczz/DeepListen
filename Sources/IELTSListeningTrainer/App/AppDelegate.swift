import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let playerStore = PlayerStore()

    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var keyEventMonitor: Any?
    private var didStart = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        start()
    }

    func start() {
        guard !didStart else { return }
        didStart = true

        NSApp.setActivationPolicy(.regular)
        configureMainMenu()
        configureKeyboardShortcuts()
        showMainWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyEventMonitor {
            NSEvent.removeMonitor(keyEventMonitor)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        showMainWindow()
        playerStore.openExternalURLs(urls)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        showMainWindow()
        playerStore.openExternalURLs([URL(fileURLWithPath: filename)])
        return true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow else { return }

        if closingWindow == mainWindow {
            mainWindow = nil
        } else if closingWindow == settingsWindow {
            settingsWindow = nil
        }
    }

    @objc func showMainWindow() {
        if let mainWindow {
            mainWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "IELTS Listening Trainer"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 960, height: 640)
        window.delegate = self
        let hostingController = NSHostingController(
            rootView: ContentView()
                .environmentObject(playerStore)
        )
        hostingController.sizingOptions = []
        window.contentViewController = hostingController
        attachTitleBarActions(to: window)
        if let visibleFrame = NSScreen.main?.visibleFrame {
            window.setFrame(
                NSRect(
                    x: visibleFrame.midX - 590,
                    y: visibleFrame.midY - 380,
                    width: 1180,
                    height: 760
                ),
                display: true
            )
        } else {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        window.display()

        mainWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    private func attachTitleBarActions(to window: NSWindow) {
        guard let frameView = window.contentView?.superview else { return }

        let addButton = TitleBarIconButton(
            systemSymbolName: "plus",
            accessibilityLabel: "添加文件或目录",
            target: self,
            action: #selector(importMedia)
        )
        addButton.toolTip = "添加文件或目录"

        let settingsButton = TitleBarIconButton(
            systemSymbolName: "gearshape",
            accessibilityLabel: "设置",
            target: self,
            action: #selector(showSettingsWindow)
        )
        settingsButton.toolTip = "设置"

        let stackView = NSStackView(views: [addButton, settingsButton])
        stackView.orientation = .horizontal
        stackView.spacing = 10
        stackView.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        frameView.addSubview(stackView, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: frameView.topAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: frameView.trailingAnchor, constant: -36)
        ])
    }

    @objc func showSettingsWindow() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "设置"
        window.isReleasedWhenClosed = false
        window.delegate = self
        let hostingController = NSHostingController(
            rootView: SettingsView()
                .environmentObject(playerStore)
        )
        hostingController.sizingOptions = []
        window.contentViewController = hostingController
        window.center()
        window.makeKeyAndOrderFront(nil)

        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func importFiles() {
        playerStore.showImportFilesPanel()
    }

    @objc private func importMedia() {
        playerStore.showImportMediaPanel()
    }

    @objc private func importFolder() {
        playerStore.showImportFolderPanel()
    }

    @objc private func clearLibrary() {
        playerStore.clearLibrary()
    }

    @objc private func togglePlayPause() {
        playerStore.togglePlayPause()
    }

    @objc private func skipBackward() {
        playerStore.skip(by: -5)
    }

    @objc private func skipForward() {
        playerStore.skip(by: 5)
    }

    @objc private func previousTrack() {
        playerStore.previousTrack()
    }

    @objc private func nextTrack() {
        playerStore.nextTrack()
    }

    @objc private func setLoopStart() {
        playerStore.setLoopStart()
    }

    @objc private func setLoopEnd() {
        playerStore.setLoopEnd()
    }

    @objc private func clearLoop() {
        playerStore.clearLoop()
    }

    @objc private func toggleSubtitles() {
        playerStore.showSubtitles.toggle()
    }

    @objc private func togglePlaybackMode() {
        switch playerStore.playbackMode {
        case .sequence:
            playerStore.playbackMode = .singleLoop
        case .singleLoop:
            playerStore.playbackMode = .sequence
        }
    }

    private func configureKeyboardShortcuts() {
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if modifiers.isEmpty {
                switch event.keyCode {
                case 49:
                    self.togglePlayPause()
                    return nil
                case 53:
                    self.clearLoop()
                    return nil
                case 123:
                    self.skipBackward()
                    return nil
                case 124:
                    self.skipForward()
                    return nil
                default:
                    break
                }

                switch event.charactersIgnoringModifiers?.lowercased() {
                case "a":
                    self.setLoopStart()
                    return nil
                case "b":
                    self.setLoopEnd()
                    return nil
                case "s":
                    self.toggleSubtitles()
                    return nil
                default:
                    break
                }
            }

            return event
        }
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        appMenu.addItem(menuItem(
            title: "关于 IELTSListeningTrainer",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:))
        ))
        appMenu.addItem(.separator())
        appMenu.addItem(menuItem(title: "设置...", action: #selector(showSettingsWindow), keyEquivalent: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(menuItem(
            title: "退出 IELTSListeningTrainer",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q",
            target: NSApp
        ))

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)

        let fileMenu = NSMenu(title: "文件")
        fileMenuItem.submenu = fileMenu
        fileMenu.addItem(menuItem(title: "显示主窗口", action: #selector(showMainWindow), keyEquivalent: "n"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(menuItem(title: "导入文件...", action: #selector(importFiles), keyEquivalent: "o"))
        fileMenu.addItem(menuItem(
            title: "添加文件或目录...",
            action: #selector(importMedia),
            keyEquivalent: "o",
            modifiers: [.command, .option]
        ))
        fileMenu.addItem(menuItem(
            title: "导入目录...",
            action: #selector(importFolder),
            keyEquivalent: "o",
            modifiers: [.command, .shift]
        ))
        fileMenu.addItem(.separator())
        fileMenu.addItem(menuItem(title: "清空列表", action: #selector(clearLibrary)))

        let playbackMenuItem = NSMenuItem()
        mainMenu.addItem(playbackMenuItem)

        let playbackMenu = NSMenu(title: "播放")
        playbackMenuItem.submenu = playbackMenu
        playbackMenu.addItem(menuItem(title: "播放/暂停", action: #selector(togglePlayPause), keyEquivalent: " ", modifiers: []))
        playbackMenu.addItem(menuItem(title: "上一首", action: #selector(previousTrack), keyEquivalent: "p"))
        playbackMenu.addItem(menuItem(title: "下一首", action: #selector(nextTrack), keyEquivalent: "n"))
        playbackMenu.addItem(.separator())
        playbackMenu.addItem(menuItem(title: "后退 5 秒", action: #selector(skipBackward)))
        playbackMenu.addItem(menuItem(title: "前进 5 秒", action: #selector(skipForward)))
        playbackMenu.addItem(.separator())
        playbackMenu.addItem(menuItem(title: "设置 A 点", action: #selector(setLoopStart), keyEquivalent: "a", modifiers: []))
        playbackMenu.addItem(menuItem(title: "设置 B 点", action: #selector(setLoopEnd), keyEquivalent: "b", modifiers: []))
        playbackMenu.addItem(menuItem(title: "清除 A/B 片段", action: #selector(clearLoop)))
        playbackMenu.addItem(menuItem(title: "显示/隐藏字幕", action: #selector(toggleSubtitles), keyEquivalent: "s", modifiers: []))
        playbackMenu.addItem(.separator())
        playbackMenu.addItem(menuItem(title: "切换播放模式", action: #selector(togglePlaybackMode)))

        NSApp.mainMenu = mainMenu
    }

    private func menuItem(
        title: String,
        action: Selector?,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = [.command],
        target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.keyEquivalentModifierMask = modifiers
        item.target = target ?? self
        return item
    }
}

private final class TitleBarIconButton: NSButton {
    override var isHighlighted: Bool {
        didSet {
            updateAppearance()
        }
    }

    init(systemSymbolName: String, accessibilityLabel: String, target: AnyObject?, action: Selector) {
        super.init(frame: NSRect(x: 0, y: 0, width: 34, height: 34))

        self.target = target
        self.action = action
        self.image = NSImage(systemSymbolName: systemSymbolName, accessibilityDescription: accessibilityLabel)
        self.imagePosition = .imageOnly
        self.imageScaling = .scaleProportionallyDown
        self.contentTintColor = .secondaryLabelColor
        self.isBordered = false
        self.focusRingType = .none
        self.translatesAutoresizingMaskIntoConstraints = false
        self.wantsLayer = true

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 34),
            heightAnchor.constraint(equalToConstant: 34)
        ])
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func updateAppearance() {
        guard let layer else { return }

        layer.cornerRadius = 9
        layer.backgroundColor = (
            isHighlighted
                ? NSColor.secondaryLabelColor.withAlphaComponent(0.18)
                : NSColor.white.withAlphaComponent(0.96)
        ).cgColor
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = isHighlighted ? 0 : 0.10
        layer.shadowRadius = isHighlighted ? 0 : 10
        layer.shadowOffset = NSSize(width: 0, height: -5)
    }
}
