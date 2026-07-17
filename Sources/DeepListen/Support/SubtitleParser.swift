import Foundation

enum SubtitleParser {
    private static let gb18030 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
    )

    static func parse(url: URL) -> [SubtitleCue] {
        guard let text = decodeText(at: url) else { return [] }
        return parse(text)
    }

    /// 按编码逐个尝试，并用"必须含有时间轴箭头"来校验结果。
    /// 关键：UTF-16 / Latin-1 对几乎任意字节都能"解码成功"但产出乱码，
    /// 只有加上这个校验才能把乱码候选排除掉，而不是把乱码当正文显示。
    private static func decodeText(at url: URL) -> String? {
        var candidates: [String] = []

        // 系统嗅探优先：能正确处理带 BOM 的 UTF-8 / UTF-16。
        var detectedEncoding = String.Encoding.utf8
        if let text = try? String(contentsOf: url, usedEncoding: &detectedEncoding) {
            candidates.append(text)
        }

        if let data = try? Data(contentsOf: url) {
            for encoding in [String.Encoding.utf8, gb18030, .utf16, .isoLatin1] {
                if let text = String(data: data, encoding: encoding) {
                    candidates.append(text)
                }
            }
        }

        return candidates.first { $0.contains("-->") }
    }

    static func parse(_ text: String) -> [SubtitleCue] {
        let normalizedText = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let blocks = normalizedText.components(separatedBy: "\n\n")
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

            let cueText = lines[(timingLineIndex + 1)...]
                .joined(separator: " ")
                .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !cueText.isEmpty else { continue }

            parsedCues.append((start: start, end: end, text: cueText))
        }

        // 必须按时间排序：PlayerStore.subtitlePosition 用二分查找定位当前句，
        // 前提是 cues 有序。乱序字幕文件会让二分查找漏掉当前句。
        return parsedCues
            .sorted { $0.start < $1.start }
            .enumerated()
            .map { offset, cue in
                SubtitleCue(index: offset + 1, start: cue.start, end: cue.end, text: cue.text)
            }
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
