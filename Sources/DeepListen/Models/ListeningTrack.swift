import Foundation

struct ListeningTrack: Identifiable, Hashable, Sendable {
    let id: UUID
    var url: URL
    var duration: TimeInterval?
    var subtitleURL: URL?
    var mediaKind: MediaKind

    init(url: URL, id: UUID = UUID(), duration: TimeInterval? = nil) {
        self.id = id
        self.url = url
        self.duration = duration
        self.subtitleURL = Self.matchingSubtitleURL(for: url)
        self.mediaKind = MediaKind(url: url)
    }

    /// 始终从当前文件名生成，改展示规则后不必重新导入。
    var title: String {
        Self.displayTitle(for: url)
    }

    var fileExtension: String {
        url.pathExtension.uppercased()
    }

    private static let indexSeparators: Set<Character> = [".", "_", "-"]

    static func displayTitle(for url: URL) -> String {
        let rawName = url.deletingPathExtension().lastPathComponent

        // 分隔符统一成空格后按空白切分：切分本身就会折叠连续分隔符
        // （如 "Adam---Dominant"）并去掉首尾空白，无需再走一次正则。
        let spaced = String(
            strippingLeadingDateStamps(from: rawName).map {
                $0 == "_" || $0 == "-" ? " " : $0
            }
        )
        let words = spaced.split(whereSeparator: \.isWhitespace)

        guard !words.isEmpty else { return rawName }
        return capitalizingLowercasedWords(in: words)
    }

    /// 只剥离日期/时间戳式前缀（连续 ≥6 位数字），保留课文序号。
    /// `20260717-081307-Adam` → `Adam`；`01.A Private Conversation` 原样留下。
    /// 要求编号后必须跟分隔符，避免把纯数字文件名整个抹掉。
    /// 手写扫描而非正则：`Regex` 不是 `Sendable`，无法作为静态存储在导入所用的
    /// detached task 间共享，而每个文件重新编译一遍正则并不划算。
    private static func strippingLeadingDateStamps(from name: String) -> Substring {
        var remainder = Substring(name)

        while true {
            let digits = remainder.prefix(while: \.isNumber)
            guard digits.count >= 6 else { return remainder }

            let afterDigits = remainder.dropFirst(digits.count)
            let separators = afterDigits.prefix {
                $0.isWhitespace || indexSeparators.contains($0)
            }
            guard !separators.isEmpty else { return remainder }

            remainder = afterDigits.dropFirst(separators.count)
        }
    }

    /// 只给全小写的词做首字母大写。含大写的词（IELTS、iPhone）原样保留——
    /// 直接用 .capitalized 会把 "IELTS" 毁成 "Ielts"。
    private static func capitalizingLowercasedWords(
        in words: some Sequence<Substring>
    ) -> String {
        words
            .map { word in
                word.contains(where: \.isUppercase) ? String(word) : String(word).capitalized
            }
            .joined(separator: " ")
    }

    static func matchingSubtitleURL(for mediaURL: URL) -> URL? {
        let baseURL = mediaURL.deletingPathExtension()
        let fileManager = FileManager.default

        for subtitleExtension in ["srt", "SRT", "vtt", "VTT", "lrc", "LRC"] {
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
