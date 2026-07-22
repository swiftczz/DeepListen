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
            eventWindow?.title == "DeepListen",
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

    private func isEditingText(in window: NSWindow?) -> Bool {
        guard let textView = window?.firstResponder as? NSTextView else { return false }
        return textView.isEditable
    }
}
