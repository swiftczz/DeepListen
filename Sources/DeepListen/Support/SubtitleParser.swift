import Foundation

enum SubtitleParser {
    private static let gb18030 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
    )

    /// 内联的字体/位置标签（`<i>`、`<c.yellow>` 等），只在正文里出现，需整体剥离。
    /// 提到循环外：`replacingOccurrences(options: .regularExpression)` 每次调用都会
    /// 重新编译一遍正则，而字幕文件动辄数百条。
    /// 用 `NSRegularExpression` 而非 `Regex` 字面量：后者不是 `Sendable`，
    /// 无法作为静态存储被解析所在的 detached task 共享。
    private static let markupTag = try! NSRegularExpression(pattern: "<[^>]+>")

    /// LRC 时间戳形如 `[00:09.77]`、`[1:23]`、`[00:01:23.45]`。
    private static let lrcTimestamp = try! NSRegularExpression(
        pattern: "\\[\\d{1,3}:\\d{2}(?:[.:]\\d{1,3}){0,2}\\]"
    )

    static func parse(url: URL, mediaDuration: TimeInterval = 0) -> [SubtitleCue] {
        guard let text = decodeText(at: url) else { return [] }
        return parse(text, mediaDuration: mediaDuration)
    }

    /// 按编码逐个尝试，命中即返回。
    /// 关键：UTF-16 / Latin-1 对几乎任意字节都能"解码成功"但产出乱码，
    /// 只有加上 `isDecodedSubtitle` 校验才能把乱码候选排除掉，而不是把乱码当正文显示。
    private static func decodeText(at url: URL) -> String? {
        // 系统嗅探优先：能正确处理带 BOM 的 UTF-8 / UTF-16。
        var detectedEncoding = String.Encoding.utf8
        if let text = try? String(contentsOf: url, usedEncoding: &detectedEncoding),
            isDecodedSubtitle(text)
        {
            return text
        }

        guard let data = try? Data(contentsOf: url) else { return nil }

        for encoding in [String.Encoding.utf8, gb18030, .utf16, .isoLatin1] {
            if let text = String(data: data, encoding: encoding), isDecodedSubtitle(text) {
                return text
            }
        }

        return nil
    }

    /// 解码结果必须含有 SRT/VTT 时间轴箭头或 LRC 时间戳，才算真正解对了编码。
    private static func isDecodedSubtitle(_ text: String) -> Bool {
        text.contains("-->") || containsLRCTimestamp(text)
    }

    private static func containsLRCTimestamp(_ text: String) -> Bool {
        lrcTimestamp.firstMatch(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        ) != nil
    }

    /// 绝大多数字幕行不含标签，先做一次廉价判断再走正则。
    private static func removingMarkupTags(from text: String) -> String {
        guard text.contains("<") else { return text }
        return markupTag.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: ""
        )
    }

    static func parse(_ text: String, mediaDuration: TimeInterval = 0) -> [SubtitleCue] {
        let normalizedText = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        if normalizedText.contains("-->") {
            return parseTimedText(normalizedText)
        }

        return parseLRC(normalizedText, mediaDuration: mediaDuration)
    }

    /// SRT / VTT：每条字幕自带起止时间。
    private static func parseTimedText(_ text: String) -> [SubtitleCue] {
        let blocks = text.components(separatedBy: "\n\n")
        var parsedCues: [(start: TimeInterval, end: TimeInterval, text: String)] = []

        for block in blocks {
            let lines = block
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)

            guard let timingLineIndex = lines.firstIndex(where: { $0.contains("-->") }) else {
                continue
            }

            let timingParts = lines[timingLineIndex].components(separatedBy: "-->")
            guard
                timingParts.count >= 2,
                let start = parseTimestamp(timingParts[0]),
                let end = parseTimestamp(timingParts[1])
            else {
                continue
            }

            let cueText = removingMarkupTags(from: lines[(timingLineIndex + 1)...].joined(separator: " "))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !cueText.isEmpty else { continue }

            parsedCues.append((start: start, end: end, text: cueText))
        }

        return makeCues(parsedCues.map { ($0.start, $0.end, $0.text, nil) })
    }

    /// LRC 只有起始时间：本句的结束取下一句的开始；末句按词数估算时长。
    /// 新概念等双语歌词常用 `英文 | 译文`，译文单独保存，不参与逐词高亮。
    private static func parseLRC(
        _ text: String,
        mediaDuration: TimeInterval
    ) -> [SubtitleCue] {
        var offset: TimeInterval = 0
        var entries: [(start: TimeInterval, text: String, translation: String?)] = []

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            let extracted = extractBracketTags(from: line)
            guard !extracted.tags.isEmpty else { continue }

            var timestamps: [TimeInterval] = []

            for tag in extracted.tags {
                if let timestamp = parseLRCTimestamp(tag) {
                    timestamps.append(timestamp)
                } else if let parsedOffset = parseLRCOffset(tag) {
                    offset = parsedOffset
                }
            }

            guard !timestamps.isEmpty else { continue }

            let lyrics = removingMarkupTags(from: extracted.remainder)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !lyrics.isEmpty else { continue }

            let bilingual = splitBilingualLyrics(lyrics)
            guard !bilingual.text.isEmpty else { continue }

            for timestamp in timestamps {
                entries.append(
                    (
                        start: timestamp,
                        text: bilingual.text,
                        translation: bilingual.translation
                    )
                )
            }
        }

        // `[offset:]` 是整份歌词的全局校正，不论它写在文件哪一行。
        if offset != 0 {
            entries = entries.map { entry in
                (
                    start: max(entry.start + offset, 0),
                    text: entry.text,
                    translation: entry.translation
                )
            }
        }

        let sorted = entries.sorted { $0.start < $1.start }
        var parsedCues: [(TimeInterval, TimeInterval, String, String?)] = []
        parsedCues.reserveCapacity(sorted.count)

        for index in sorted.indices {
            let entry = sorted[index]
            let end: TimeInterval
            if let nextStart = sorted[(index + 1)...].first(where: { $0.start > entry.start })?.start {
                end = nextStart
            } else if mediaDuration > entry.start {
                end = mediaDuration
            } else {
                end = entry.start + estimatedDuration(for: entry.text)
            }

            parsedCues.append((entry.start, end, entry.text, entry.translation))
        }

        return makeCues(parsedCues)
    }

    private static func makeCues(
        _ parsedCues: [(start: TimeInterval, end: TimeInterval, text: String, translation: String?)]
    ) -> [SubtitleCue] {
        // 必须按时间排序：PlayerStore.subtitlePosition 用二分查找定位当前句，
        // 前提是 cues 有序。乱序字幕文件会让二分查找漏掉当前句。
        parsedCues
            .sorted { $0.start < $1.start }
            .enumerated()
            .map { offset, cue in
                SubtitleCue(
                    index: offset + 1,
                    start: cue.start,
                    end: cue.end,
                    text: cue.text,
                    translation: cue.translation
                )
            }
    }

    /// 从行首连续取出 `[...]` 标签，返回标签内容和剩余正文。
    private static func extractBracketTags(
        from line: String
    ) -> (tags: [String], remainder: String) {
        var tags: [String] = []
        var index = line.startIndex

        while index < line.endIndex {
            while index < line.endIndex, line[index].isWhitespace {
                line.formIndex(after: &index)
            }

            guard index < line.endIndex, line[index] == "[" else { break }
            guard let closeIndex = line[index...].firstIndex(of: "]") else { break }

            let contentStart = line.index(after: index)
            tags.append(String(line[contentStart..<closeIndex]))
            index = line.index(after: closeIndex)
        }

        return (tags, String(line[index...]))
    }

    /// `[mm:ss]`、`[mm:ss.xx]`、`[hh:mm:ss.xxx]`。分钟可超过 59（部分 LRC 用总分钟数）。
    private static func parseLRCTimestamp(_ tag: String) -> TimeInterval? {
        parseTimestamp(tag)
    }

    /// `[offset:500]` / `[offset:-250]`，单位毫秒，校正整份歌词的时间轴。
    private static func parseLRCOffset(_ tag: String) -> TimeInterval? {
        let prefix = "offset:"
        guard tag.lowercased().hasPrefix(prefix) else { return nil }

        let rawValue = tag.dropFirst(prefix.count)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let milliseconds = Double(rawValue) else { return nil }
        return milliseconds / 1000
    }

    /// 新概念 LRC 用 `|` 分隔英文和中文；只按首个分隔符切开，避免误伤正文。
    private static func splitBilingualLyrics(
        _ lyrics: String
    ) -> (text: String, translation: String?) {
        guard let separator = lyrics.range(of: "|") else {
            return (lyrics, nil)
        }

        let text = lyrics[..<separator.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let translation = lyrics[separator.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (text, translation.isEmpty ? nil : translation)
    }

    /// 末句没有下一句可作结束点，按英语语速约 2 词/秒估算，最少 3 秒。
    private static func estimatedDuration(for text: String) -> TimeInterval {
        let wordCount = max(text.split(whereSeparator: \.isWhitespace).count, 1)
        return max(3, Double(wordCount) * 0.5 + 1)
    }

    private static func parseTimestamp(_ rawTimestamp: String) -> TimeInterval? {
        let timestamp = rawTimestamp
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .first
            .map(String.init)?
            .replacingOccurrences(of: ",", with: ".")

        guard let timestamp else { return nil }

        let components = timestamp.split(separator: ":").map(String.init)
        guard components.count == 2 || components.count == 3 else { return nil }

        let hours: Double
        let minutes: Double
        let seconds: Double

        if components.count == 3 {
            guard
                let parsedHours = Double(components[0]),
                let parsedMinutes = Double(components[1]),
                let parsedSeconds = Double(components[2])
            else {
                return nil
            }

            hours = parsedHours
            minutes = parsedMinutes
            seconds = parsedSeconds
        } else {
            guard
                let parsedMinutes = Double(components[0]),
                let parsedSeconds = Double(components[1])
            else {
                return nil
            }

            hours = 0
            minutes = parsedMinutes
            seconds = parsedSeconds
        }

        return hours * 3600 + minutes * 60 + seconds
    }
}
