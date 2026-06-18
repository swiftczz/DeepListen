import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
delegate.start()
app.finishLaunching()
withExtendedLifetime(delegate) {
    app.run()
}
