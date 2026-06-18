import AppKit
import Foundation

protocol FileRevealing {
    func revealInFinder(_ url: URL)
}

struct MacFileRevealer: FileRevealing {
    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
