import AudioToolbox
import AVFoundation
import Foundation

/// Swift demuxing plus Apple's media writer; no subprocesses or third-party decoding libraries.
enum NativeMatroskaAudioExporter {
    static func export(source: URL, destination: URL) async throws {
        let reader = try MatroskaAudioReader(url: source)
        let configuration = try AudioConfiguration(track: reader.track)
        if configuration.isMP3 {
            try await exportMP3(reader, configuration: configuration, destination: destination)
            return
        }
        let format = try configuration.makeFormatDescription()
        let writer = try AVAssetWriter(outputURL: destination, fileType: .m4a)
        let input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: configuration.outputSettings,
            sourceFormatHint: format
        )
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { throw MatroskaAudioError.unsupportedCodec(reader.track.codec) }
        writer.add(input)
        guard writer.startWriting() else { throw failure(writer) }
        writer.startSession(atSourceTime: .zero)
        var runs: [AudioRun] = []
        var totalFrames: Int64 = 0
        let rate = configuration.asbd.mSampleRate
        var batch = Data()
        var packetSizes: [Int] = []
        var batchFrames = 0
        batch.reserveCapacity(64 * 1024)
        packetSizes.reserveCapacity(128)
        func flush() throws {
            guard !packetSizes.isEmpty else { return }
            let sample = try configuration.makeSample(batch, packetSizes: packetSizes,
                frames: batchFrames, startFrame: totalFrames - Int64(batchFrames), format: format)
            try append(sample, to: input, writer: writer)
            batch.removeAll(keepingCapacity: true)
            packetSizes.removeAll(keepingCapacity: true)
            batchFrames = 0
        }
        do {
            try reader.readFrames(
                frameDuration: { try configuration.frameDuration($0) },
                consume: { frame, timestamp in
                    let frames = Int64((try configuration.frameDuration(frame) * rate).rounded())
                    try recordRun(timestamp: timestamp, frames: frames, totalFrames: totalFrames,
                        rate: rate, runs: &runs)
                    // One CoreMedia buffer can carry many original packets. Keep individual AAC
                    // sample sizes so batching changes neither encoded bytes nor sample boundaries.
                    batch.append(frame)
                    packetSizes.append(frame.count)
                    batchFrames += Int(frames)
                    totalFrames += frames
                    if packetSizes.count >= 128 || batch.count >= 1_048_576 { try flush() }
                }
            )
            try flush()
            try Task.checkCancellation()
            input.markAsFinished()
            await writer.finishWriting()
            try Task.checkCancellation()
            guard writer.status == .completed else { throw failure(writer) }
            // Compressed packet writing can collapse gaps. Preserve the original Matroska timeline
            // with native composition edits after writing a continuous, sample-accurate audio stream.
            if runs.count > 1 || abs(runs[0].timestamp) > 0.003 {
                let packed = destination.deletingPathExtension().appendingPathExtension("packed.m4a")
                try FileManager.default.moveItem(at: destination, to: packed)
                defer { try? FileManager.default.removeItem(at: packed) }
                try await exportTimeline(streamURL: packed, runs: runs, rate: rate,
                    preset: AVAssetExportPresetAppleM4A, destination: destination)
            }
        } catch {
            if writer.status == .writing || writer.status == .unknown { writer.cancelWriting() }
            try Task.checkCancellation()
            throw error
        }
    }

    private static func append(_ sample: CMSampleBuffer, to input: AVAssetWriterInput, writer: AVAssetWriter) throws {
        // Runs inside MediaPlaybackPreparer's detached worker, never on the UI thread.
        // Bound the wait to detect a stalled writer instead of leaving preparation spinning forever.
        let deadline = ContinuousClock.now + .seconds(15)
        while !input.isReadyForMoreMediaData {
            try Task.checkCancellation()
            guard writer.status == .writing, ContinuousClock.now < deadline else { throw failure(writer) }
            Thread.sleep(forTimeInterval: 0.001)
        }
        guard input.append(sample) else { throw failure(writer) }
    }

    private static func failure(_ writer: AVAssetWriter) -> MatroskaAudioError {
        .writingFailed(writer.error?.localizedDescription ?? "系统音频写入失败。")
    }

    private struct AudioRun {
        var timestamp: Double
        var mediaStart: Int64
        var frames: Int64
    }

    private static func recordRun(timestamp: Double, frames: Int64, totalFrames: Int64,
        rate: Double, runs: inout [AudioRun]
    ) throws {
        guard timestamp.isFinite, abs(timestamp) < 10 * 365 * 24 * 3600 else {
            throw MatroskaAudioError.invalidFile("音频时间戳无效。")
        }
        if let run = runs.last {
            let expected = run.timestamp + Double(run.frames) / rate
            if abs(timestamp - expected) > 0.003 {
                guard timestamp >= expected else {
                    throw MatroskaAudioError.invalidFile("音频时间戳发生重叠。")
                }
                runs.append(AudioRun(timestamp: timestamp, mediaStart: totalFrames, frames: 0))
            }
        } else {
            runs.append(AudioRun(timestamp: timestamp, mediaStart: 0, frames: 0))
        }
        runs[runs.count - 1].frames += frames
    }

    private static func exportMP3(_ reader: MatroskaAudioReader, configuration: AudioConfiguration,
        destination: URL
    ) async throws {
        // Apple's M4A writer cannot accept MP3 packets directly. Stage a native MP3 stream, then let
        // AVFoundation decode and export it. Composition edits preserve initial delays and real gaps.
        let streamURL = destination.deletingPathExtension().appendingPathExtension("mp3")
        _ = FileManager.default.createFile(atPath: streamURL.path, contents: nil)
        let stream = try FileHandle(forWritingTo: streamURL)
        defer {
            try? stream.close()
            try? FileManager.default.removeItem(at: streamURL)
        }
        var runs: [AudioRun] = []
        var totalFrames: Int64 = 0
        let rate = reader.track.sampleRate
        var batch = Data()
        batch.reserveCapacity(1_048_576)
        try reader.readFrames(frameDuration: { try configuration.frameDuration($0) }) { packet, timestamp in
            let frames = Int64((try configuration.frameDuration(packet) * rate).rounded())
            try recordRun(timestamp: timestamp, frames: frames, totalFrames: totalFrames,
                rate: rate, runs: &runs)
            totalFrames += frames
            batch.append(packet)
            if batch.count >= 1_048_576 {
                try stream.write(contentsOf: batch)
                batch.removeAll(keepingCapacity: true)
            }
        }
        if !batch.isEmpty { try stream.write(contentsOf: batch) }
        try stream.close()
        try Task.checkCancellation()
        try await exportTimeline(streamURL: streamURL, runs: runs, rate: rate,
            preset: AVAssetExportPresetAppleM4A, destination: destination)
    }

    private static func exportTimeline(streamURL: URL, runs: [AudioRun], rate: Double,
        preset: String, destination: URL
    ) async throws {
        let asset = AVURLAsset(url: streamURL)
        guard let sourceTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw MatroskaAudioError.noAudio
        }
        let available = try await sourceTrack.load(.timeRange)
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw MatroskaAudioError.writingFailed("无法创建 MP3 音轨。")
        }
        for run in runs {
            try Task.checkCancellation()
            let trim = max(0, -run.timestamp)
            let start = CMTime(seconds: Double(run.mediaStart) / rate + trim, preferredTimescale: 1_000_000_000)
            let duration = min(Double(run.frames) / rate - trim, available.end.seconds - start.seconds)
            guard duration > 0 else { continue }
            try track.insertTimeRange(
                CMTimeRange(start: start, duration: CMTime(seconds: duration, preferredTimescale: 1_000_000_000)),
                of: sourceTrack, at: CMTime(seconds: max(0, run.timestamp), preferredTimescale: 1_000_000_000)
            )
        }
        guard let export = AVAssetExportSession(asset: composition, presetName: preset) else {
            throw MatroskaAudioError.writingFailed("系统无法导出音频时间轴。")
        }
        try await export.export(to: destination, as: .m4a)
        try Task.checkCancellation()
    }

    private struct AudioConfiguration {
        var asbd: AudioStreamBasicDescription
        var cookie = Data()
        var outputSettings: [String: Any]?
        var isPCM = false
        var isMP3 = false

        init(track: MatroskaAudioTrack) throws {
            asbd = AudioStreamBasicDescription()
            asbd.mSampleRate = track.sampleRate
            asbd.mChannelsPerFrame = UInt32(track.channels)
            switch track.codec {
            case "A_AAC":
                var bits = BitReader(data: track.codecPrivate)
                let profile = try bits.read(5)
                let frequencyIndex = try bits.read(4)
                let rates: [UInt32] = [96_000, 88_200, 64_000, 48_000, 44_100, 32_000,
                    24_000, 22_050, 16_000, 12_000, 11_025, 8_000, 7_350]
                let rate: UInt32
                if frequencyIndex == 15 { rate = UInt32(try bits.read(24)) }
                else {
                    guard frequencyIndex < rates.count else { throw MatroskaAudioError.invalidFile("AAC 采样率无效。") }
                    rate = rates[frequencyIndex]
                }
                let channelConfiguration = try bits.read(4)
                let channels = channelConfiguration == 7 ? 8 : channelConfiguration
                guard profile == 2, rate > 0, channels > 0, channels <= 8 else {
                    throw MatroskaAudioError.unsupportedCodec("AAC profile \(profile)")
                }
                let shortFrame = try bits.read(1) != 0
                asbd.mSampleRate = Double(rate)
                asbd.mChannelsPerFrame = UInt32(channels)
                asbd.mFormatID = kAudioFormatMPEG4AAC
                asbd.mFramesPerPacket = shortFrame ? 960 : 1024
                cookie = Self.aacCookie(track.codecPrivate)
            case "A_MPEG/L3":
                isMP3 = true
                asbd.mFormatID = kAudioFormatMPEGLayer3
                asbd.mFramesPerPacket = track.sampleRate < 32_000 ? 576 : 1152
            case "A_PCM/INT/LIT", "A_PCM/INT/BIG", "A_PCM/FLOAT/IEEE":
                isPCM = true
                let isFloat = track.codec == "A_PCM/FLOAT/IEEE"
                guard (isFloat ? [32, 64] : [16, 24, 32]).contains(track.bitDepth), track.channels <= 8 else {
                    throw MatroskaAudioError.unsupportedCodec("\(track.codec) / \(track.bitDepth) bit")
                }
                asbd.mFormatID = kAudioFormatLinearPCM
                asbd.mFormatFlags = kAudioFormatFlagIsPacked
                    | (isFloat ? kAudioFormatFlagIsFloat : kAudioFormatFlagIsSignedInteger)
                if track.codec == "A_PCM/INT/BIG" { asbd.mFormatFlags |= kAudioFormatFlagIsBigEndian }
                asbd.mBitsPerChannel = UInt32(track.bitDepth)
                asbd.mFramesPerPacket = 1
                asbd.mBytesPerFrame = UInt32(track.bitDepth / 8 * track.channels)
                asbd.mBytesPerPacket = asbd.mBytesPerFrame
                outputSettings = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: track.sampleRate,
                    AVNumberOfChannelsKey: min(track.channels, 2),
                    AVEncoderBitRateKey: 192_000,
                ]
            default:
                throw MatroskaAudioError.unsupportedCodec(track.codec)
            }
        }

        func frameDuration(_ frame: Data) throws -> Double {
            Double(try frameCount(frame)) / asbd.mSampleRate
        }

        private func frameCount(_ frame: Data) throws -> Int {
            if isPCM {
                guard frame.count % Int(asbd.mBytesPerFrame) == 0 else {
                    throw MatroskaAudioError.invalidFile("PCM 音频帧不完整。")
                }
                return frame.count / Int(asbd.mBytesPerFrame)
            }
            if isMP3 {
                guard frame.count >= 4, frame[0] == 0xFF, frame[1] & 0xE0 == 0xE0,
                    (frame[1] >> 1) & 3 == 1, (frame[1] >> 3) & 3 != 1
                else { throw MatroskaAudioError.invalidFile("MP3 音频帧无效。") }
                return (frame[1] >> 3) & 3 == 3 ? 1152 : 576
            }
            return Int(asbd.mFramesPerPacket)
        }

        func makeFormatDescription() throws -> CMAudioFormatDescription {
            var description: CMAudioFormatDescription?
            var asbd = asbd
            let status = cookie.withUnsafeBytes { bytes in
                CMAudioFormatDescriptionCreate(
                    allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil,
                    magicCookieSize: cookie.count, magicCookie: bytes.baseAddress,
                    extensions: nil, formatDescriptionOut: &description
                )
            }
            guard status == noErr, let description else {
                throw MatroskaAudioError.writingFailed("无法创建音频格式（\(status)）。")
            }
            return description
        }

        func makeSample(_ frame: Data, packetSizes: [Int], frames: Int, startFrame: Int64,
            format: CMAudioFormatDescription
        ) throws -> CMSampleBuffer {
            var block: CMBlockBuffer?
            var status = CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: frame.count,
                blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
                offsetToData: 0, dataLength: frame.count, flags: 0, blockBufferOut: &block
            )
            guard status == noErr, let block else {
                throw MatroskaAudioError.writingFailed("无法创建音频缓冲区（\(status)）。")
            }
            status = frame.withUnsafeBytes { bytes in
                CMBlockBufferReplaceDataBytes(with: bytes.baseAddress!, blockBuffer: block,
                    offsetIntoDestination: 0, dataLength: frame.count)
            }
            guard status == noErr else { throw MatroskaAudioError.writingFailed("音频数据写入失败（\(status)）。") }
            let sampleRate = CMTimeScale(asbd.mSampleRate.rounded())
            var timing = CMSampleTimingInfo(
                duration: CMTime(value: isPCM ? 1 : Int64(asbd.mFramesPerPacket), timescale: sampleRate),
                presentationTimeStamp: CMTime(value: startFrame, timescale: sampleRate),
                decodeTimeStamp: .invalid
            )
            let sizes = isPCM ? [Int(asbd.mBytesPerFrame)] : packetSizes
            var sample: CMSampleBuffer?
            status = sizes.withUnsafeBufferPointer { sizes in
                CMSampleBufferCreateReady(
                    allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
                    sampleCount: isPCM ? frames : packetSizes.count,
                    sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                    sampleSizeEntryCount: sizes.count, sampleSizeArray: sizes.baseAddress,
                    sampleBufferOut: &sample
                )
            }
            guard status == noErr, let sample else {
                throw MatroskaAudioError.writingFailed("无法创建音频样本（\(status)）。")
            }
            return sample
        }

        // Apple's AAC cookie is an MPEG-4 ES descriptor containing the original AudioSpecificConfig.
        private static func aacCookie(_ config: Data) -> Data {
            let decoder = descriptor(0x04, Data([0x40, 0x15, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
                + descriptor(0x05, config))
            return descriptor(0x03, Data([0, 1, 0]) + decoder + descriptor(0x06, Data([2])))
        }

        private static func descriptor(_ tag: UInt8, _ payload: Data) -> Data {
            var value = payload.count
            var length = [UInt8(value & 0x7F)]
            value >>= 7
            while value > 0 { length.insert(UInt8(value & 0x7F) | 0x80, at: 0); value >>= 7 }
            return Data([tag] + length) + payload
        }
    }

    private struct BitReader {
        var data: Data
        var position = 0

        mutating func read(_ count: Int) throws -> Int {
            guard count <= data.count * 8 - position else {
                throw MatroskaAudioError.invalidFile("AAC 配置信息不完整。")
            }
            var value = 0
            for _ in 0..<count {
                value = value << 1 | Int((data[position / 8] >> (7 - position % 8)) & 1)
                position += 1
            }
            return value
        }
    }
}
