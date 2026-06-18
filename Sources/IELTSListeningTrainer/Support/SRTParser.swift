import Foundation

enum SRTParser {
    static func parse(url: URL) -> [SubtitleCue] {
        if let utf8Text = try? String(contentsOf: url, encoding: .utf8) {
            return parse(utf8Text)
        }

        if let utf16Text = try? String(contentsOf: url, encoding: .utf16) {
            return parse(utf16Text)
        }

        if let latinText = try? String(contentsOf: url, encoding: .isoLatin1) {
            return parse(latinText)
        }

        return []
    }

    static func parse(_ text: String) -> [SubtitleCue] {
        let normalizedText = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let blocks = normalizedText.components(separatedBy: "\n\n")
        var cues: [SubtitleCue] = []

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

            cues.append(SubtitleCue(index: cues.count + 1, start: start, end: end, text: cueText))
        }

        return cues
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
