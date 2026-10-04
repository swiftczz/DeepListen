import Foundation
import Testing
@testable import DeepListen

@Suite(.serialized) @MainActor
struct FavoritesTests {
    private func defaults() throws -> (UserDefaults, String) {
        let suite = "FavoritesTests-\(UUID())"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }
    private func passage(start: Double = 0.2) -> SavedPassage {
        SavedPassage(sourcePath: "/missing/lesson.mkv", sourceTitle: "Lesson", start: start, end: start + 0.3,
            text: "A difficult sentence.", translation: "一个难句。")
    }

    @Test func persistenceDeduplicationAndMissingSource() throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FavoritesStore(defaults: defaults)
        let first = passage()
        #expect(store.add(first) == first.id)
        store.updateNote("连读要注意", for: first.id)
        store.setMastered(true, for: first.id)
        #expect(store.add(passage()) == first.id)
        #expect(store.add(passage(start: .nan)) == nil)
        let restored = FavoritesStore(defaults: defaults)
        #expect(restored.passages.count == 1)
        #expect(restored.selected?.note == "连读要注意")
        #expect(restored.selected?.isMastered == true)
        #expect(restored.selected?.sourceExists == false)
        #expect(restored.visiblePassages.count == 1)
        restored.searchText = "连读"
        #expect(restored.visiblePassages.count == 1)
        restored.searchText = "不存在的关键词"
        #expect(restored.visiblePassages.isEmpty)
    }

    @Test func reviewQueueHidesAnswersAndRetainsSkippedPassages() throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FavoritesStore(defaults: defaults)
        let first = passage(), second = passage(start: 1), mastered = passage(start: 2)
        [first, second, mastered].forEach { store.add($0) }
        store.setMastered(true, for: mastered.id)
        store.startReview()
        #expect(store.reviewQueue == [second.id, first.id])
        #expect(store.hidesAnswer)
        store.reveal()
        #expect(!store.hidesAnswer)
        store.advance(mastered: false)
        #expect(store.selectedID == first.id)
        #expect(store.hidesAnswer)
        store.advance(mastered: true)
        #expect(store.isReviewComplete)
        #expect(store.pendingCount == 1)
        #expect(store.reviewedCount == 1)
        store.stopReview()
        store.startReview()
        #expect(store.reviewQueue == [second.id])
        store.remove(second.id)
        #expect(store.isReviewComplete)
    }

    @Test func relinkUpdatesAllPassagesFromOneSource() throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FavoritesStore(defaults: defaults)
        let first = passage(), second = passage(start: 1)
        [first, second].forEach { store.add($0) }
        let fixture = try #require(Bundle.module.url(forResource: "aac", withExtension: "mkv", subdirectory: "Fixtures"))
        store.relink(first.id, to: fixture)
        #expect(store.passages.allSatisfy { $0.sourceExists && $0.sourceURL == fixture })
        #expect(store.passages.map(\.id) == [second.id, first.id])
    }

    @Test func manualABCaptureAndRapidPlaybackSwitching() async throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FavoritesSwitchTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try #require(Bundle.module.url(forResource: "aac", withExtension: "mkv", subdirectory: "Fixtures"))
        let source = directory.appendingPathComponent("lesson.mkv")
        try FileManager.default.copyItem(at: fixture, to: source)
        try "1\n00:00:00,100 --> 00:00:00,500\nFirst line\n\n2\n00:00:00,600 --> 00:00:01,000\nSecond line\n".write(
            to: source.deletingPathExtension().appendingPathExtension("srt"), atomically: true, encoding: .utf8)
        let track = ListeningTrack(url: source, duration: 2)
        let persistence = PlayerPersistence(defaults: defaults)
        persistence.saveLibrary(tracks: [track], selectedTrackID: track.id)
        let preparer = MediaPlaybackPreparer(cacheDirectory: directory.appendingPathComponent("cache"))
        let player = PlayerStore(persistence: persistence, mediaPreparer: preparer,
            playbackEngine: PlaybackEngine(isMuted: true))
        for _ in 0..<200 where player.isPreparingMedia || player.subtitleLoadState == .loading {
            try await Task.sleep(for: .milliseconds(10))
        }
        player.seek(to: 0.2)
        let sentence = try #require(player.favoriteCandidate)
        #expect(!sentence.isClip && sentence.text == "First line")
        player.seek(to: 0.3)
        player.setLoopStart()
        player.seek(to: 0.9)
        player.setLoopEnd()
        let clip = try #require(player.favoriteCandidate)
        #expect(clip.isClip && clip.text == "First line\nSecond line")
        #expect(clip.start == 0.3 && clip.end == 0.9)
        player.loadFavorite(sentence, autoplay: true)
        player.loadFavorite(clip, autoplay: true)
        player.leaveFavoritePlayback()
        for _ in 0..<200 where player.isPreparingMedia { try await Task.sleep(for: .milliseconds(10)) }
        #expect(player.activeFavorite == nil)
        #expect(player.selectedTrack?.id == track.id)
        #expect(player.currentTime == 0.9)
        #expect(!player.isPlaying)
        #expect(player.mediaPreparationError == nil)
        player.loadFavorite(clip, autoplay: true)
        player.removeTrack(track.id)
        try await Task.sleep(for: .milliseconds(100))
        #expect(player.activeFavorite?.id == clip.id)
        #expect(!player.isPlaying && !player.isPreparingMedia)
        #expect(try preparer.cachedPlaybackURL(for: source) == nil)
    }

    @Test func favoritePlaybackPreservesLibraryPositionAndBounds() async throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FavoritesPlaybackTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try #require(Bundle.module.url(forResource: "aac", withExtension: "mkv", subdirectory: "Fixtures"))
        let source = directory.appendingPathComponent("lesson.mkv")
        try FileManager.default.copyItem(at: fixture, to: source)
        let track = ListeningTrack(url: source, duration: 2)
        let persistence = PlayerPersistence(defaults: defaults)
        persistence.saveLibrary(tracks: [track], selectedTrackID: track.id)
        persistence.savePlaybackPosition(1.2, for: track.id)
        let player = PlayerStore(persistence: persistence,
            mediaPreparer: MediaPlaybackPreparer(cacheDirectory: directory.appendingPathComponent("cache")),
            playbackEngine: PlaybackEngine(isMuted: true))
        var favorite = passage()
        favorite.sourcePath = source.path
        let favorites = FavoritesStore(defaults: defaults)
        favorites.add(favorite)
        player.loadFavorite(favorite)
        for _ in 0..<200 where player.isPreparingMedia { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!player.isPreparingMedia)
        #expect(player.mediaPreparationError == nil)
        #expect(player.currentTime == favorite.start)
        player.seek(to: 100)
        #expect(player.currentTime == favorite.end)
        player.seek(to: -100)
        #expect(player.currentTime == favorite.start)
        player.savePlaybackPosition()
        #expect(persistence.playbackPosition(for: track.id) == 1.2)
        player.setFavoriteLooping(false)
        player.play()
        try await Task.sleep(for: .milliseconds(900))
        #expect(!player.isPlaying)
        #expect(player.currentTime == favorite.end)
        player.setFavoriteLooping(true)
        player.replayFavorite()
        try await Task.sleep(for: .milliseconds(800))
        #expect(player.isPlaying)
        #expect(player.currentTime >= favorite.start && player.currentTime <= favorite.end)
        player.pause()
        player.leaveFavoritePlayback()
        #expect(player.currentTime == 1.2)
        player.removeTrack(track.id)
        #expect(FavoritesStore(defaults: defaults).passages == [favorite])
        player.loadFavorite(favorite)
        #expect(player.tracks.isEmpty)
        for _ in 0..<200 where player.isPreparingMedia { try await Task.sleep(for: .milliseconds(10)) }
        #expect(player.mediaPreparationError == nil)
        player.pause()
        var invalid = favorite
        invalid.start = 100
        invalid.end = 101
        player.loadFavorite(invalid, autoplay: true)
        for _ in 0..<200 where player.isPreparingMedia { try await Task.sleep(for: .milliseconds(10)) }
        #expect(player.mediaPreparationError?.contains("超出") == true)
        #expect(!player.isPlaying)
        player.play()
        #expect(!player.isPlaying)
        player.leaveFavoritePlayback()
    }
}
