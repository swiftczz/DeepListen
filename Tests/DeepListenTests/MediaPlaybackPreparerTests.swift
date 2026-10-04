import AVFoundation
import CryptoKit
import Foundation
import Testing
@testable import DeepListen

struct MediaPlaybackPreparerTests {
    private func workspace() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeepListenTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func fixture(in directory: URL, codec: String = "aac") throws -> URL {
        let bundled = try #require(Bundle.module.url(forResource: codec, withExtension: "mkv", subdirectory: "Fixtures"))
        let source = directory.appendingPathComponent("测试 movie \(codec).MKV")
        try FileManager.default.copyItem(at: bundled, to: source)
        return source
    }

    @Test func nativeMediaBypassesPreparation() async throws {
        let source = URL(fileURLWithPath: "/unused/audio.mp4")
        #expect(try await MediaPlaybackPreparer().prepare(source) == source)
    }

    @Test(arguments: [false, true])
    func copiesAACWithoutChangingPacketsAndReusesCache(longAudio: Bool) async throws {
        let directory = try workspace()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try fixture(in: directory)
        if longAudio { _ = try extendAudio(at: source) }
        let cache = directory.appendingPathComponent("cache")
        let preparer = MediaPlaybackPreparer(cacheDirectory: cache)
        let output = try await preparer.prepare(source)
        #expect(output.pathExtension == "m4a")
        #expect(try await AVURLAsset(url: output).load(.isPlayable))
        #expect(try #require(await MediaDurationLoader.loadDuration(for: output)) > 1.9)
        #expect(try await preparer.prepare(source) == output)
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: cache.path).count == 1)

        var original = SHA256()
        var originalSizes: [Int] = []
        try MatroskaAudioReader(url: source).readFrames(frameDuration: { _ in 1024.0 / 44_100 }) {
            packet, _ in
            original.update(data: packet)
            originalSizes.append(packet.count)
        }
        let asset = AVURLAsset(url: output)
        let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let assetReader = try AVAssetReader(asset: asset)
        let audio = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        assetReader.add(audio)
        #expect(assetReader.startReading())
        var prepared = SHA256()
        var preparedSizes: [Int] = []
        while let sample = audio.copyNextSampleBuffer() {
            // Edit-list gaps can be returned as empty sample buffers rather than audio packets.
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var packet = Data(count: length)
            let status = packet.withUnsafeMutableBytes { bytes in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: bytes.baseAddress!)
            }
            #expect(status == noErr)
            prepared.update(data: packet)
            for index in 0..<CMSampleBufferGetNumSamples(sample) {
                preparedSizes.append(CMSampleBufferGetSampleSize(sample, at: index))
            }
        }
        #expect(assetReader.status == .completed)
        #expect(original.finalize() == prepared.finalize())
        #expect(originalSizes == preparedSizes)
    }

    /// Exercise multiple full batches and a final partial batch with valid, varied codec packets.
    private func extendAudio(at source: URL) throws -> Double {
        let reader = try MatroskaAudioReader(url: source)
        func duration(_ packet: Data) -> Double {
            let frames: Double
            switch reader.track.codec {
            case "A_MPEG/L3": frames = (packet[1] >> 3) & 3 == 3 ? 1152 : 576
            case "A_PCM/INT/LIT": frames = Double(packet.count) / Double(reader.track.bitDepth / 8 * reader.track.channels)
            default: frames = 1024
            }
            return frames / reader.track.sampleRate
        }
        var original: [Data] = []
        try reader.readFrames(frameDuration: duration) { packet, _ in original.append(packet) }
        let packets = (0..<417).map { original[$0 % original.count] }
        var clusters = Data()
        var time = 0.0
        for start in stride(from: 0, to: packets.count, by: 200) {
            let group = Array(packets[start..<min(start + 200, packets.count)])
            clusters += MatroskaTestFile.cluster(time: UInt64((time * 1000).rounded()),
                blocks: MatroskaTestFile.block(packets: group, mode: 1))
            time += group.reduce(0) { $0 + duration($1) }
        }
        let track = MatroskaTestFile.track(codec: reader.track.codec, sampleRate: reader.track.sampleRate,
            channels: reader.track.channels, cookie: reader.track.codecPrivate, bitDepth: reader.track.bitDepth)
        try MatroskaTestFile.make(clusters: clusters, audioTrack: track).write(to: source)
        return time
    }

    @Test(arguments: ["mp3", "pcm"])
    func preparesOtherNativeCodecs(codec: String) async throws {
        let directory = try workspace()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try fixture(in: directory, codec: codec)
        let expectedDuration = try extendAudio(at: source)
        let output = try await MediaPlaybackPreparer(cacheDirectory: directory.appendingPathComponent("cache")).prepare(source)
        #expect(try await AVURLAsset(url: output).load(.isPlayable))
        let duration = try #require(await MediaDurationLoader.loadDuration(for: output))
        #expect(abs(duration - expectedDuration) < 0.05)
    }

    @Test @MainActor func preparedAudioSupportsEngineSeekingAndPlayback() async throws {
        let directory = try workspace()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try fixture(in: directory)
        let output = try await MediaPlaybackPreparer(cacheDirectory: directory.appendingPathComponent("cache")).prepare(source)
        let engine = PlaybackEngine()
        var position: TimeInterval = 0
        engine.configure(handlers: .init(tick: { position = $0 }, finished: {}))
        engine.replaceCurrentItem(with: output)
        engine.seek(to: 0.5)
        engine.play(rate: 0.5)
        try await Task.sleep(for: .seconds(1))
        engine.pause()
        #expect(position > 0.7)
        #expect(position < 1.2)
    }

    @Test func sourceChangeInvalidatesCache() async throws {
        let directory = try workspace()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try fixture(in: directory)
        let preparer = MediaPlaybackPreparer(cacheDirectory: directory.appendingPathComponent("cache"))
        let original = try await preparer.prepare(source)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 60)], ofItemAtPath: source.path)
        #expect(try preparer.cachedPlaybackURL(for: source) == nil)
        #expect(try await preparer.prepare(source) != original)
    }

    @Test(arguments: [false, true])
    func removesAllSourceRevisionsEvenWhenSourceIsMissing(missingSource: Bool) async throws {
        let directory = try workspace()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try fixture(in: directory)
        let otherSource = try fixture(in: directory, codec: "mp3")
        let preparer = MediaPlaybackPreparer(cacheDirectory: directory.appendingPathComponent("cache"))
        let first = try await preparer.prepare(source)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 60)], ofItemAtPath: source.path)
        let second = try await preparer.prepare(source)
        let other = try await preparer.prepare(otherSource)
        if missingSource { try FileManager.default.removeItem(at: source) }
        try preparer.removeCachedAudio(for: source)
        try preparer.removeCachedAudio(for: source) // Repeated removal is harmless.
        #expect(!FileManager.default.fileExists(atPath: first.path))
        #expect(!FileManager.default.fileExists(atPath: second.path))
        #expect(FileManager.default.fileExists(atPath: other.path))
        #expect(FileManager.default.fileExists(atPath: source.path) == !missingSource)
        #expect(FileManager.default.fileExists(atPath: otherSource.path))
        try preparer.removeCachedAudio(for: other) // A normal audio URL never deletes the source.
        #expect(FileManager.default.fileExists(atPath: other.path))
    }

    @Test func migratesAndRemovesLegacyCache() async throws {
        let directory = try workspace()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try fixture(in: directory)
        let cache = directory.appendingPathComponent("cache")
        let preparer = MediaPlaybackPreparer(cacheDirectory: cache)
        let output = try await preparer.prepare(source)
        let legacy = cache.appendingPathComponent(output.lastPathComponent)
        try FileManager.default.moveItem(at: output, to: legacy)
        #expect(try preparer.cachedPlaybackURL(for: source) == legacy)
        #expect(try await preparer.prepare(source) == output)
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        try FileManager.default.copyItem(at: output, to: legacy)
        try preparer.removeCachedAudio(for: source)
        #expect(!FileManager.default.fileExists(atPath: output.path))
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test func invalidMediaDoesNotPublishCache() async throws {
        let directory = try workspace()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("broken.mkv")
        try Data("invalid".utf8).write(to: source)
        let cache = directory.appendingPathComponent("cache")
        do {
            _ = try await MediaPlaybackPreparer(cacheDirectory: cache).prepare(source)
            Issue.record("Expected invalid media error")
        } catch {
            #expect(error is MatroskaAudioError)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: cache.path).isEmpty)
    }

    @Test func cancelledPreparationDoesNotPublishCache() async throws {
        let directory = try workspace()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try fixture(in: directory)
        let cache = directory.appendingPathComponent("cache")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await MediaPlaybackPreparer(cacheDirectory: cache).prepare(source)
        }
        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch { #expect(error is CancellationError) }
        #expect(!FileManager.default.fileExists(atPath: cache.path))
    }

    @Test(arguments: ["aac", "mp3"])
    func preservesAudioDelayAndGaps(codec: String) async throws {
        let directory = try workspace()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = try MatroskaAudioReader(url: fixture(in: directory, codec: codec))
        let samplesPerPacket = codec == "aac" ? 1024.0 : 1152.0
        var packets: [Data] = []
        try original.readFrames(frameDuration: { _ in samplesPerPacket / original.track.sampleRate }) {
            packet, _ in if packets.count < 20 { packets.append(packet) }
        }
        let cluster1 = MatroskaTestFile.cluster(time: 1000,
            blocks: MatroskaTestFile.block(packets: packets, mode: 1))
        let cluster2 = MatroskaTestFile.cluster(time: 2000,
            blocks: MatroskaTestFile.block(packets: packets, mode: 3))
        let track = MatroskaTestFile.track(codec: original.track.codec,
            sampleRate: original.track.sampleRate, channels: original.track.channels,
            cookie: original.track.codecPrivate)
        let source = directory.appendingPathComponent("gaps.mkv")
        try MatroskaTestFile.make(clusters: cluster1 + cluster2, audioTrack: track).write(to: source)
        let output = try await MediaPlaybackPreparer(cacheDirectory: directory.appendingPathComponent("cache")).prepare(source)
        let expected = 2 + Double(packets.count) * samplesPerPacket / original.track.sampleRate
        let duration = try #require(await MediaDurationLoader.loadDuration(for: output))
        #expect(abs(duration - expected) < 0.05)
        let asset = AVURLAsset(url: output)
        let outputTrack = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let assetReader = try AVAssetReader(asset: asset)
        let audio = AVAssetReaderTrackOutput(track: outputTrack, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: original.track.sampleRate,
            AVNumberOfChannelsKey: original.track.channels,
        ])
        assetReader.add(audio)
        #expect(assetReader.startReading())
        var leadingAmplitude: Float = 0
        var gapAmplitude: Float = 0
        var audibleAmplitude: Float = 0
        while let sample = audio.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var bytes = Data(count: length)
            let status = bytes.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!)
            }
            #expect(status == noErr)
            let start = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            let channels = Int(original.track.channels)
            bytes.withUnsafeBytes { samples in
                for index in 0..<(length / 4) {
                    let time = start + Double(index / channels) / original.track.sampleRate
                    let amplitude = abs(samples.loadUnaligned(fromByteOffset: index * 4, as: Float.self))
                    if time < 0.9 { leadingAmplitude = max(leadingAmplitude, amplitude) }
                    if time > 1.7, time < 1.9 { gapAmplitude = max(gapAmplitude, amplitude) }
                    if time > 1.1, time < 1.3 { audibleAmplitude = max(audibleAmplitude, amplitude) }
                }
            }
        }
        #expect(assetReader.status == .completed)
        #expect(leadingAmplitude < 0.0001)
        #expect(gapAmplitude < 0.0001)
        #expect(audibleAmplitude > 0.001)
    }

    @Test func unsupportedCodecShowsExplicitError() async throws {
        let directory = try workspace()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("opus.mkv")
        let data = MatroskaTestFile.make(clusters: MatroskaTestFile.cluster(time: 0,
            blocks: MatroskaTestFile.block(packets: [Data([1])])), codec: "A_OPUS")
        try data.write(to: source)
        do {
            _ = try await MediaPlaybackPreparer(cacheDirectory: directory.appendingPathComponent("cache")).prepare(source)
            Issue.record("Accepted unsupported Opus codec")
        } catch { #expect(error.localizedDescription.contains("A_OPUS")) }
    }

    @Test(arguments: ["cancel", "remove", "clear"])
    func cancellingActivePreparationCleansUpPartialCache(action: String) async throws {
        let directory = try workspace()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = try MatroskaAudioReader(url: fixture(in: directory))
        var packet = Data()
        try original.readFrames(frameDuration: { _ in 1024.0 / original.track.sampleRate }) {
            frame, _ in if packet.isEmpty { packet = frame }
        }
        var clusters = Data()
        for index in 0..<500 {
            let block = MatroskaTestFile.block(packets: Array(repeating: packet, count: 200), mode: 2)
            let time = UInt64((Double(index * 200) * 1024 / original.track.sampleRate * 1000).rounded())
            clusters += MatroskaTestFile.cluster(time: time, blocks: block)
        }
        let track = MatroskaTestFile.track(sampleRate: original.track.sampleRate,
            channels: original.track.channels, cookie: original.track.codecPrivate)
        let source = directory.appendingPathComponent("long.mkv")
        try MatroskaTestFile.make(clusters: clusters, audioTrack: track).write(to: source)
        let cache = directory.appendingPathComponent("cache")
        let preparer = MediaPlaybackPreparer(cacheDirectory: cache)
        let task = Task { try await preparer.prepare(source) }
        // Wait until the worker has created its private output directory, then cancel in-flight work.
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: cache.path) { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        switch action {
        case "remove": try preparer.removeCachedAudio(for: source)
        case "clear": try preparer.removeAllCachedAudio()
        default: task.cancel()
        }
        do {
            _ = try await task.value
            Issue.record("Expected active preparation cancellation")
        } catch {
            #expect(error is CancellationError || (action == "clear" && error is MatroskaAudioError))
        }
        let remaining = (try? FileManager.default.contentsOfDirectory(atPath: cache.path)) ?? []
        #expect(remaining.isEmpty)
    }
}
