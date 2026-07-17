import Foundation

struct ListeningTrack: Identifiable, Hashable, Sendable {
    let id: UUID
    var url: URL
    var title: String
    var duration: TimeInterval?
    var subtitleURL: URL?
    var mediaKind: MediaKind

    init(url: URL, id: UUID = UUID(), duration: TimeInterval? = nil) {
        self.id = id
        self.url = url
        self.title = Self.displayTitle(for: url)
        self.duration = duration
        self.subtitleURL = Self.matchingSubtitleURL(for: url)
        self.mediaKind = MediaKind(url: url)
    }

    var fileExtension: String {
        url.pathExtension.uppercased()
    }

    static func displayTitle(for url: URL) -> String {
        let rawName = url.deletingPathExtension().lastPathComponent

        let spaced = strippingLeadingIndexes(from: rawName)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            // 连续分隔符（如 "Adam---Dominant"）折叠成单个空格
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !spaced.isEmpty else { return rawName }
        return capitalizingLowercasedWords(in: spaced)
    }

    /// 反复剥离前导编号段（日期、序号等），例如 "20260717-081307-Adam" → "Adam"。
    /// 要求编号后必须跟分隔符，避免把纯数字文件名整个抹掉。
    private static func strippingLeadingIndexes(from name: String) -> String {
        var result = name
        while true {
            let stripped = result.replacingOccurrences(
                of: #"^\d+[\s._-]+"#,
                with: "",
                options: .regularExpression
            )
            if stripped == result {
                return result
            }
            result = stripped
        }
    }

    /// 只给全小写的词做首字母大写。含大写的词（IELTS、iPhone）原样保留——
    /// 直接用 .capitalized 会把 "IELTS" 毁成 "Ielts"。
    private static func capitalizingLowercasedWords(in text: String) -> String {
        text
            .split(separator: " ")
            .map { word in
                word.contains(where: \.isUppercase) ? String(word) : String(word).capitalized
            }
            .joined(separator: " ")
    }

    static func matchingSubtitleURL(for mediaURL: URL) -> URL? {
        let baseURL = mediaURL.deletingPathExtension()
        let fileManager = FileManager.default

        for subtitleExtension in ["srt", "SRT", "vtt", "VTT"] {
            let candidate = baseURL.appendingPathExtension(subtitleExtension)
            if fileManager.fileExists(atPath: candidate.path(percentEncoded: false)) {
                return candidate
            }
        }

        return nil
    }
}

enum MediaKind: String, Codable, Sendable {
    case audio
    case video

    init(url: URL) {
        let videoExtensions: Set<String> = ["mp4", "m4v", "mov", "avi", "mkv"]
        self = videoExtensions.contains(url.pathExtension.lowercased()) ? .video : .audio
    }

    var label: String {
        switch self {
        case .audio:
            return "音频"
        case .video:
            return "视频"
        }
    }
}
