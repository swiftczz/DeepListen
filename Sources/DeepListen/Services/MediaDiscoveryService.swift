import Foundation
import UniformTypeIdentifiers

struct MediaDiscoveryResult: Sendable {
    var addedTracks: [ListeningTrack]
    var firstTargetID: ListeningTrack.ID?
    var playableCount: Int
}

enum MediaDiscoveryService {
    static let playableExtensions = [
        "mp3", "m4a", "aac", "wav", "aiff", "aif", "caf", "flac",
        "mp4", "m4v", "mov", "avi", "mkv",
    ]

    private static let playableExtensionSet = Set(playableExtensions)

    static let importableContentTypes = playableExtensions.compactMap {
        UTType(filenameExtension: $0)
    } + [.folder]

    static func discover(
        from urls: [URL],
        existingTracks: [ListeningTrack]
    ) -> MediaDiscoveryResult {
        let mediaURLs = discoverPlayableMediaURLs(from: urls)
        var knownMediaIDsByKey = mediaIDsByKey(for: existingTracks)
        var firstTargetID: ListeningTrack.ID?
        var addedTracks: [ListeningTrack] = []

        for mediaURL in mediaURLs {
            guard !Task.isCancelled else { break }

            let mediaKey = mediaIdentityKey(for: mediaURL)
            if let existingTrackID = knownMediaIDsByKey[mediaKey] {
                if firstTargetID == nil {
                    firstTargetID = existingTrackID
                }
                continue
            }

            let track = ListeningTrack(url: mediaURL)
            addedTracks.append(track)
            knownMediaIDsByKey[mediaKey] = track.id
            if firstTargetID == nil {
                firstTargetID = track.id
            }
        }

        return MediaDiscoveryResult(
            addedTracks: addedTracks,
            firstTargetID: firstTargetID,
            playableCount: mediaURLs.count
        )
    }

    static func isPlayableMediaURL(_ url: URL) -> Bool {
        playableExtensionSet.contains(url.pathExtension.lowercased())
    }

    /// 用文件系统的唯一标识做去重键：同一文件的不同路径（软链、别名）命中同一 key，
    /// 而不同目录下的同名同大小文件（如各 Test 目录里的 "Section 1.mp3"）不会被误判成重复。
    /// 旧实现用"文件名+大小"，会把这类文件静默跳过导入。
    static func mediaIdentityKey(for url: URL) -> String {
        if let identifier = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey])
            .fileResourceIdentifier
        {
            return "id:\(identifier)"
        }

        // 回退：文件不可访问时按标准化全路径区分。
        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
        let path = url.standardizedFileURL.path(percentEncoded: false).lowercased()
        return "path:\(path)#\(fileSize)"
    }

    private static func discoverPlayableMediaURLs(from urls: [URL]) -> [URL] {
        var mediaURLs: [URL] = []
        let fileManager = FileManager.default

        for url in urls {
            guard !Task.isCancelled else { break }
            guard let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey]) else {
                continue
            }

            if resourceValues.isDirectory == true {
                let keys: [URLResourceKey] = [.isRegularFileKey, .isHiddenKey]
                guard
                    let enumerator = fileManager.enumerator(
                        at: url,
                        includingPropertiesForKeys: keys,
                        options: [.skipsHiddenFiles, .skipsPackageDescendants]
                    )
                else {
                    continue
                }

                for case let childURL as URL in enumerator {
                    guard !Task.isCancelled else {
                        enumerator.skipDescendants()
                        break
                    }
                    guard
                        let values = try? childURL.resourceValues(forKeys: Set(keys)),
                        values.isRegularFile == true,
                        values.isHidden != true,
                        isPlayableMediaURL(childURL)
                    else {
                        continue
                    }
                    mediaURLs.append(childURL)
                }
            } else if isPlayableMediaURL(url) {
                mediaURLs.append(url)
            }
        }

        return mediaURLs.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    private static func mediaIDsByKey(
        for tracks: [ListeningTrack]
    ) -> [String: ListeningTrack.ID] {
        Dictionary(
            tracks.map { (mediaIdentityKey(for: $0.url), $0.id) },
            uniquingKeysWith: { firstID, _ in firstID }
        )
    }
}
