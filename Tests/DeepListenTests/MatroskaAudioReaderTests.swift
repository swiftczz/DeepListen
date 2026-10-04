import Foundation
import Testing
@testable import DeepListen

enum MatroskaTestFile {
    static func element(_ id: UInt32, _ payload: Data, unknown: Bool = false) -> Data {
        var big = id.bigEndian
        let bytes = withUnsafeBytes(of: &big) { Data($0) }.drop(while: { $0 == 0 })
        return Data(bytes) + (unknown ? Data([0xFF]) : vint(UInt64(payload.count))) + payload
    }

    static func vint(_ value: UInt64) -> Data {
        var length = 1
        while value >= (UInt64(1) << (7 * length)) - 1 { length += 1 }
        let encoded = value | UInt64(1) << (7 * length)
        return Data((0..<length).reversed().map { UInt8(truncatingIfNeeded: encoded >> ($0 * 8)) })
    }

    static func uint(_ value: UInt64) -> Data {
        var big = value.bigEndian
        let bytes = withUnsafeBytes(of: &big) { Data($0) }.drop(while: { $0 == 0 })
        return bytes.isEmpty ? Data([0]) : Data(bytes)
    }

    static func track(codec: String = "A_AAC", type: UInt64 = 2, encoded: Bool = false,
        sampleRate: Double = 48_000, channels: UInt64 = 2, cookie: Data = Data([0x11, 0x90]),
        bitDepth: UInt64 = 0
    ) -> Data {
        var rate = sampleRate.bitPattern.bigEndian
        let audio = element(0xB5, withUnsafeBytes(of: &rate) { Data($0) }) + element(0x9F, uint(channels))
            + (bitDepth > 0 ? element(0x6264, uint(bitDepth)) : Data())
        return element(0xAE,
            element(0xD7, uint(130)) + element(0x83, uint(type))
                + element(0x86, Data(codec.utf8)) + element(0x63A2, cookie)
                + element(0xE1, audio) + (encoded ? element(0x6D80, Data()) : Data()))
    }

    static func block(packets: [Data], mode: UInt8 = 0, relative: Int16 = 0, group: Bool = false) -> Data {
        var timing = relative.bigEndian
        var payload = vint(130) + withUnsafeBytes(of: &timing) { Data($0) } + Data([mode << 1])
        if mode != 0 {
            payload.append(UInt8(packets.count - 1))
            if mode == 1 {
                for packet in packets.dropLast() {
                    payload += Data(repeating: 255, count: packet.count / 255) + Data([UInt8(packet.count % 255)])
                }
            } else if mode == 3 {
                payload += vint(UInt64(packets[0].count))
                for index in 1..<(packets.count - 1) {
                    let difference = packets[index].count - packets[index - 1].count
                    var length = 1
                    var bias = 63
                    while difference < -bias || difference > bias {
                        length += 1
                        bias = (1 << (7 * length - 1)) - 1
                    }
                    payload += vint(UInt64(difference + bias))
                }
            }
        }
        for packet in packets { payload += packet }
        return group ? element(0xA0, element(0xA1, payload)) : element(0xA3, payload)
    }

    static func cluster(time: UInt64, blocks: Data, unknown: Bool = false) -> Data {
        element(0x1F43B675, element(0xE7, uint(time)) + blocks, unknown: unknown)
    }

    static func make(clusters: Data, codec: String = "A_AAC", unknown: Bool = false,
        encoded: Bool = false, type: UInt64 = 2, audioTrack: Data? = nil
    ) -> Data {
        let header = element(0x1A45DFA3, element(0x4282, Data("matroska".utf8)))
        let info = element(0x1549A966, element(0x2AD7B1, uint(1_000_000)))
        return header + element(0x18538067, info + element(0x1654AE6B,
            audioTrack ?? track(codec: codec, type: type, encoded: encoded)) + clusters, unknown: unknown)
    }
}

struct MatroskaAudioReaderTests {
    @Test(arguments: [UInt8(0), 1, 2, 3])
    func readsAllLacingModesAndSignedTimestamps(mode: UInt8) throws {
        let packets: [Data] = mode == 0 ? [Data([1, 2, 3])]
            : mode == 2 ? [Data([1, 2, 3]), Data([4, 5, 6]), Data([7, 8, 9])]
            : [Data([1, 2, 3]), Data([4, 5, 6, 7]), Data([8, 9])]
        let file = MatroskaTestFile.make(clusters: MatroskaTestFile.cluster(time: 100,
            blocks: MatroskaTestFile.block(packets: packets, mode: mode, relative: -10)))
        let reader = try MatroskaAudioReader(data: file)
        var read: [Data] = []
        var times: [Double] = []
        try reader.readFrames(frameDuration: { _ in 1024.0 / 48_000 }) { packet, time in
            read.append(packet); times.append(time)
        }
        #expect(read == packets)
        #expect(reader.track.number == 130)
        for index in times.indices {
            #expect(abs(times[index] - (0.09 + Double(index) * 1024.0 / 48_000)) < 0.000001)
        }
    }

    @Test func handlesUnknownSizeSegmentAndClustersAndBlockGroups() throws {
        let clusters = MatroskaTestFile.cluster(time: 100,
            blocks: MatroskaTestFile.block(packets: [Data([1])]), unknown: true)
            + MatroskaTestFile.cluster(time: 200,
                blocks: MatroskaTestFile.block(packets: [Data([2])], group: true), unknown: true)
        let reader = try MatroskaAudioReader(data: MatroskaTestFile.make(clusters: clusters, unknown: true))
        var times: [Double] = []
        try reader.readFrames(frameDuration: { _ in 0.02 }) { _, time in times.append(time) }
        #expect(times == [0.1, 0.2])
    }

    @Test func truncatedElementsFailWithoutReadingPastBounds() throws {
        let file = MatroskaTestFile.make(clusters: MatroskaTestFile.cluster(time: 100,
            blocks: MatroskaTestFile.block(packets: [Data([1, 2, 3])])))
        for length in 0..<file.count {
            do {
                _ = try MatroskaAudioReader(data: Data(file.prefix(length)))
                Issue.record("Accepted truncated file at \(length)")
            } catch { #expect(error is MatroskaAudioError) }
        }
    }

    @Test(arguments: [Data([0, 1]), Data([1, 4, 5]), Data([1, 0xFF]), Data([1, 0, 1, 2])])
    func malformedLacesFail(data: Data) {
        for mode: UInt8 in [1, 2, 3] {
            var offset = 0
            do {
                let sizes = try MatroskaAudioReader.laceSizes(in: data, at: &offset, limit: data.count, mode: mode)
                #expect(sizes.allSatisfy { $0 > 0 })
                #expect(sizes.reduce(0, +) == data.count - offset)
            } catch { #expect(error is MatroskaAudioError) }
        }
    }

    @Test func rejectsEncodedAudioAndFilesWithoutAudio() {
        do {
            _ = try MatroskaAudioReader(data: MatroskaTestFile.make(clusters: Data(), encoded: true))
            Issue.record("Accepted encoded audio")
        } catch { #expect(error.localizedDescription.contains("加密")) }
        do {
            _ = try MatroskaAudioReader(data: MatroskaTestFile.make(clusters: Data(), type: 1))
            Issue.record("Accepted video-only file")
        } catch { #expect(error.localizedDescription.contains("没有可用音轨")) }
    }
}
