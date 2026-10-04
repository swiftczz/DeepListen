import Foundation
import Testing
@testable import DeepListen

@Suite(.serialized) @MainActor
struct PlayerStoreCacheTests {
    @Test(arguments: ["single-current", "single-other", "batch", "clear", "preparing"])
    func removalCleansOnlyGeneratedAudio(action: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DeepListenStoreTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "DeepListenStoreTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let fixture = try #require(Bundle.module.url(forResource: "aac", withExtension: "mkv", subdirectory: "Fixtures"))
        let sources = ["first.mkv", "second.mkv"].map { directory.appendingPathComponent($0) }
        for source in sources { try FileManager.default.copyItem(at: fixture, to: source) }
        let subtitle = sources[0].deletingPathExtension().appendingPathExtension("srt")
        let subtitleData = Data("1\n00:00:00,000 --> 00:00:01,000\nTest\n".utf8)
        try subtitleData.write(to: subtitle)
        let tracks = sources.map { ListeningTrack(url: $0, duration: 2) }
        let cache = directory.appendingPathComponent("cache")
        let preparer = MediaPlaybackPreparer(cacheDirectory: cache)
        var outputs: [URL] = []
        if action != "preparing" {
            for source in sources { outputs.append(try await preparer.prepare(source)) }
        }
        let persistence = PlayerPersistence(defaults: defaults)
        persistence.saveLibrary(tracks: tracks, selectedTrackID: tracks[0].id)
        let store = PlayerStore(persistence: persistence, mediaPreparer: preparer)
        if action != "preparing" {
            for _ in 0..<100 where store.isPreparingMedia {
                try await Task.sleep(for: .milliseconds(5))
            }
            #expect(!store.isPreparingMedia)
        }
        switch action {
        case "single-other": store.removeTrack(tracks[1].id)
        case "batch": store.removeTracks(Set(tracks.map(\.id)))
        case "clear": store.clearLibrary()
        default: store.removeTrack(tracks[0].id)
        }
        if action == "preparing" {
            // The cancelled first-track job must not publish after its scheduled task resumes.
            for _ in 0..<100 where store.isPreparingMedia {
                try await Task.sleep(for: .milliseconds(5))
            }
            #expect(try preparer.cachedPlaybackURL(for: sources[0]) == nil)
        } else {
            for index in sources.indices {
                let retained = store.tracks.contains { $0.id == tracks[index].id }
                #expect(FileManager.default.fileExists(atPath: outputs[index].path) == retained)
            }
        }
        #expect(store.libraryNotice == nil)
        #expect(persistence.loadLibrary().tracks.map(\.id) == store.tracks.map(\.id))
        for source in sources { #expect(FileManager.default.fileExists(atPath: source.path)) }
        #expect(try Data(contentsOf: subtitle) == subtitleData)
    }
}
