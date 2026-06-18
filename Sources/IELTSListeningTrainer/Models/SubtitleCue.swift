import Foundation

struct SubtitleCue: Identifiable, Hashable {
    let index: Int
    let start: TimeInterval
    let end: TimeInterval
    let text: String

    var id: Int { index }
}
