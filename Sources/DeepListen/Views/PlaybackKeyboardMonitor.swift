import AppKit

/// 在播放器主窗口范围内处理无需修饰键的真实键盘事件。
/// 它不依赖菜单命令或某个 SwiftUI 控件持续持有焦点。
@MainActor
final class PlaybackKeyboardMonitor {
    var isEnabled = true

    private weak var player: PlayerStore?
    private var eventMonitor: Any?

    isolated deinit {
        stop()
    }

    func start(player: PlayerStore) {
        self.player = player
        guard eventMonitor == nil else { return }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            self?.handle(event) ?? event
        }
    }

    func stop() {
        guard let eventMonitor else { return }
        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        let eventWindow = event.window ?? NSApp.keyWindow

        guard isEnabled,
            isPlayerWindow(eventWindow),
            player?.selectedTrack != nil,
            event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
            !isEditingText(in: eventWindow)
        else {
            return event
        }

        switch event.keyCode {
        case 49: // 空格
            guard !event.isARepeat else { return nil }
            player?.togglePlayPause()
            return nil
        case 123: // 左方向键
            player?.skip(by: -5)
            return nil
        case 124: // 右方向键
            player?.skip(by: 5)
            return nil
        default:
            return event
        }
    }

    /// 不能用窗口标题字符串判断：NavigationSplitView 选中曲目后，
    /// 系统常把 `NSWindow.title` 改成课文名，左右键就会全部失效。
    private func isPlayerWindow(_ window: NSWindow?) -> Bool {
        guard let window, window.isVisible else { return false }
        if window is NSPanel { return false }
        guard window.styleMask.contains(.titled) else { return false }

        if window.identifier?.rawValue == "main" { return true }
        if window === NSApp.mainWindow { return true }
        return window === NSApp.keyWindow
    }

    /// 搜索框等真正在输入时才让出方向键。
    /// 字幕的可选中文本也是 NSTextView，但不是 field editor，不能因此禁用快进快退。
    private func isEditingText(in window: NSWindow?) -> Bool {
        guard let responder = window?.firstResponder else { return false }

        if let textView = responder as? NSTextView {
            return textView.isFieldEditor && textView.isEditable
        }

        if let textField = responder as? NSTextField {
            return textField.isEditable
        }

        return false
    }
}
