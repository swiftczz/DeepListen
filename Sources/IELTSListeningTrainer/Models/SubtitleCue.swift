import Foundation

struct SubtitleCue: Identifiable, Hashable {
    var index: Int
    var start: TimeInterval
    var end: TimeInterval
    var text: String

    var id: Int { index }
}
