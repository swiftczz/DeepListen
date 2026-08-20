import Foundation

struct SubtitleCue: Identifiable, Hashable {
    let index: Int
    let start: TimeInterval
    let end: TimeInterval
    let text: String
    /// 双语 LRC 里 `|` 后面的译文；SRT/VTT 没有对应内容。
    let translation: String?

    var id: Int { index }

    init(
        index: Int,
        start: TimeInterval,
        end: TimeInterval,
        text: String,
        translation: String? = nil
    ) {
        self.index = index
        self.start = start
        self.end = end
        self.text = text
        self.translation = translation
    }
}
