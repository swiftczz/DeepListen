import AVFoundation
import CryptoKit
import Foundation
import Synchronization

/// Keep the library and subtitles tied to the original file; only playback uses the cached audio.
struct MediaPlaybackPreparer: Sendable {
    private let cacheDirectory: URL
    private struct CacheState {
        var sourceGenerations: [String: UInt64] = [:]
        var directoryGenerations: [String: UInt64] = [:]
    }
    // Coordinate removal and publication across preparer instances. A removed track's old job
    // must never recreate its cache, even if it finishes just as the user removes the track.
    private static let state = Mutex(CacheState())

    init(
        cacheDirectory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.chengzhong.DeepListen/Audio", isDirectory: true)
    ) {
        self.cacheDirectory = cacheDirectory.standardizedFileURL.resolvingSymlinksInPath()
    }

    static func needsPreparation(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "mkv"
    }

    func cachedPlaybackURL(for source: URL) throws -> URL? {
        guard Self.needsPreparation(source) else { return source }
        let urls = [try cacheURL(for: source)] + (try legacyCacheURLs(for: source).suffix(1))
        return urls.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    func removeCachedAudio(for source: URL) throws {
        guard Self.needsPreparation(source) else { return }
        let directory = sourceCacheDirectory(for: source)
        // Removing the source directory does not require the original file to still exist.
        let legacy = (try? legacyCacheURLs(for: source)) ?? []
        try Self.state.withLock { state in
            state.sourceGenerations[directory.path, default: 0] &+= 1
            for url in [directory] + legacy { try removeIfPresent(url) }
        }
    }

    func removeAllCachedAudio() throws {
        try Self.state.withLock { state in
            state.directoryGenerations[cacheDirectory.path, default: 0] &+= 1
            try removeIfPresent(cacheDirectory)
        }
    }

    func prepare(_ source: URL) async throws -> URL {
        guard Self.needsPreparation(source) else { return source }
        try Task.checkCancellation()
        let directory = sourceCacheDirectory(for: source)
        let generation = Self.state.withLock {
            ($0.sourceGenerations[directory.path, default: 0],
             $0.directoryGenerations[cacheDirectory.path, default: 0])
        }
        func checkGeneration(_ state: CacheState) throws {
            try Task.checkCancellation()
            guard state.sourceGenerations[directory.path, default: 0] == generation.0,
                state.directoryGenerations[cacheDirectory.path, default: 0] == generation.1
            else { throw CancellationError() }
        }
        let destination = try cacheURL(for: source)
        if let cached = try cachedPlaybackURL(for: source), await isPlayableAudio(cached) {
            return try Self.state.withLock { state in
                try checkGeneration(state)
                if cached != destination {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    if !FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.moveItem(at: cached, to: destination)
                    }
                }
                return destination
            }
        }
        try Task.checkCancellation()

        let fileManager = FileManager.default
        // Each job owns its temporary output, so cancelling or switching tracks cannot publish a partial cache.
        let workDirectory = cacheDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try Self.state.withLock { state in
            try checkGeneration(state)
            try fileManager.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        }
        defer { try? fileManager.removeItem(at: workDirectory) }
        let output = workDirectory.appendingPathComponent("audio.m4a")
        let worker = Task.detached(priority: .userInitiated) {
            try await NativeMatroskaAudioExporter.export(source: source, destination: output)
        }
        try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
        guard await isPlayableAudio(output) else {
            throw MatroskaAudioError.writingFailed("系统无法播放这条音轨。")
        }
        try Task.checkCancellation()
        // Recheck in case another instance finished preparing the same file.
        let existingIsPlayable = await isPlayableAudio(destination)
        return try Self.state.withLock { state in
            try checkGeneration(state)
            if existingIsPlayable, fileManager.fileExists(atPath: destination.path) { return destination }
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try removeIfPresent(destination)
            try fileManager.moveItem(at: output, to: destination)
            return destination
        }
    }

    private func cacheURL(for source: URL) throws -> URL {
        let filename = try legacyCacheURLs(for: source).last!.lastPathComponent
        return sourceCacheDirectory(for: source).appendingPathComponent(filename)
    }

    private func sourceCacheDirectory(for source: URL) -> URL {
        let canonical = source.standardizedFileURL.resolvingSymlinksInPath()
        return cacheDirectory.appendingPathComponent(Self.hash(canonical.path), isDirectory: true)
    }

    private func legacyCacheURLs(for source: URL) throws -> [URL] {
        let canonical = source.standardizedFileURL.resolvingSymlinksInPath()
        let values = try canonical.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let identity = "\(canonical.path)|\(values.fileSize ?? 0)|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        return ["", "native-v2|", "native-v4|"].map {
            cacheDirectory.appendingPathComponent(Self.hash($0 + identity)).appendingPathExtension("m4a")
        }
    }

    private static func hash(_ identity: String) -> String {
        SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func removeIfPresent(_ url: URL) throws {
        do { try FileManager.default.removeItem(at: url) }
        catch let error as CocoaError where error.code == .fileNoSuchFile { }
    }

    private func isPlayableAudio(_ url: URL) async -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let asset = AVURLAsset(url: url)
        guard let playable = try? await asset.load(.isPlayable), playable,
            let tracks = try? await asset.loadTracks(withMediaType: .audio), !tracks.isEmpty,
            let duration = try? await asset.load(.duration),
            duration.seconds.isFinite, duration.seconds > 0
        else { return false }
        return true
    }

}
