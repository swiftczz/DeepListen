import Foundation

struct ListeningTrack: Identifiable, Codable, Hashable {
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
        let withoutIndex = rawName.replacingOccurrences(
            of: #"^\d+[\s._-]*"#,
            with: "",
            options: .regularExpression
        )
        let spaced = withoutIndex
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return spaced.isEmpty ? rawName : spaced.capitalized
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

enum MediaKind: String, Codable {
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
