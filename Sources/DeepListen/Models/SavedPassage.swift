import Foundation

struct SavedPassage: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var sourcePath: String
    var sourceTitle: String
    var start: TimeInterval
    var end: TimeInterval
    var text: String
    var translation: String?
    var isClip: Bool = false
    var note: String = ""
    var isMastered: Bool = false
    var createdAt: Date = Date()
    var lastReviewedAt: Date?

    var sourceURL: URL { URL(fileURLWithPath: sourcePath) }
    var sourceExists: Bool { FileManager.default.fileExists(atPath: sourcePath) }
    var timeLabel: String { "\(start.formattedPlaybackTime) – \(end.formattedPlaybackTime)" }
    var isValid: Bool { start.isFinite && end.isFinite && start >= 0 && end > start }

    func matches(_ other: SavedPassage) -> Bool {
        sourcePath == other.sourcePath && abs(start - other.start) < 0.001 && abs(end - other.end) < 0.001
    }
}

enum ListeningWorkspace: String, CaseIterable, Identifiable {
    case library, favorites
    var id: Self { self }
    var title: String { self == .library ? "媒体库" : "收藏" }
    var symbol: String { self == .library ? "music.note.list" : "star" }
}
