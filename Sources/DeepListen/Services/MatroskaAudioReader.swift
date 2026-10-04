import Foundation

enum MatroskaAudioError: LocalizedError {
    case invalidFile(String)
    case noAudio
    case unsupportedCodec(String)
    case unsupportedEncoding
    case writingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidFile(let detail): return "无法读取 MKV：\(detail)"
        case .noAudio: return "MKV 文件中没有可用音轨。"
        case .unsupportedCodec(let codec):
            return "暂不支持这条 MKV 音轨的编码（\(codec)）。目前支持 AAC-LC、MP3 和 PCM。"
        case .unsupportedEncoding: return "暂不支持经过加密或额外压缩的 MKV 音轨。"
        case .writingFailed(let detail): return "无法准备 MKV 音轨：\(detail)"
        }
    }
}

struct MatroskaAudioTrack {
    var number: UInt64 = 0
    var type: UInt64 = 0
    var enabled = true
    var codec = ""
    var codecPrivate = Data()
    var sampleRate: Double = 8_000
    var channels: UInt64 = 1
    var bitDepth: UInt64 = 0
    var defaultDuration: Double?
    var timestampScale: Double = 1
    var codecDelay: Double = 0
    var hasContentEncoding = false
}

/// Bounded EBML parsing. The file is memory mapped; video payloads are skipped without copying them.
/// Layout and lacing: https://www.matroska.org/technical/notes.html
struct MatroskaAudioReader {
    let data: Data
    let track: MatroskaAudioTrack
    private let segment: Range<Int>
    private let timestampScale: Double
    private static let segmentLevelIDs: Set<UInt64> = [
        0x114D9B74, 0x1549A966, 0x1654AE6B, 0x1F43B675,
        0x1C53BB6B, 0x1941A469, 0x1043A770, 0x1254C367,
    ]

    init(url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    init(data: Data) throws {
        self.data = data
        var position = 0
        let header = try Self.element(in: data, at: &position, limit: data.count)
        guard header.id == 0x1A45DFA3, !header.unknown else {
            throw MatroskaAudioError.invalidFile("缺少 EBML 文件头。")
        }
        var docType: String?
        try Self.children(in: data, range: header.payload) { child in
            if child.id == 0x4282 { docType = try Self.string(in: data, range: child.payload) }
        }
        guard docType == "matroska" || docType == "webm" else {
            throw MatroskaAudioError.invalidFile("不是 Matroska 文件。")
        }
        position = header.payload.upperBound
        var segmentRange: Range<Int>?
        while position < data.count {
            let element = try Self.element(in: data, at: &position, limit: data.count)
            if element.id == 0x18538067 { segmentRange = element.payload; break }
            guard !element.unknown else { throw Self.invalidSize() }
            position = element.payload.upperBound
        }
        guard let segmentRange else { throw Self.invalidSize() }
        segment = segmentRange
        position = segmentRange.lowerBound
        var scale: Double = 0.001 // Default TimestampScale: 1,000,000 nanoseconds.
        var tracks: [MatroskaAudioTrack] = []
        while position < segmentRange.upperBound {
            try Task.checkCancellation()
            let element = try Self.element(in: data, at: &position, limit: segmentRange.upperBound)
            switch element.id {
            case 0x1549A966:
                try Self.children(in: data, range: element.payload) { child in
                    if child.id == 0x2AD7B1 {
                        scale = Double(try Self.uint(in: data, range: child.payload)) / 1_000_000_000
                    }
                }
            case 0x1654AE6B:
                try Self.children(in: data, range: element.payload) { child in
                    if child.id == 0xAE { tracks.append(try Self.readTrack(in: data, range: child.payload)) }
                }
            default: break
            }
            position = try Self.end(of: element, in: data)
        }
        guard scale.isFinite, scale > 0 else { throw Self.invalidSize() }
        timestampScale = scale
        guard let track = tracks.first(where: { $0.type == 2 && $0.enabled && $0.number > 0 }) else {
            throw MatroskaAudioError.noAudio
        }
        guard !track.hasContentEncoding else { throw MatroskaAudioError.unsupportedEncoding }
        guard track.sampleRate.isFinite, track.sampleRate > 0, track.sampleRate <= 384_000,
            track.channels > 0, track.channels <= 64,
            track.timestampScale.isFinite, track.timestampScale > 0
        else { throw Self.invalidSize() }
        self.track = track
    }

    /// Each callback receives one codec packet, even when a Block contains multiple laced packets.
    func readFrames(
        frameDuration: (Data) throws -> Double,
        consume: (Data, Double) throws -> Void
    ) throws {
        var position = segment.lowerBound
        var count = 0
        while position < segment.upperBound {
            try Task.checkCancellation()
            let element = try Self.element(in: data, at: &position, limit: segment.upperBound)
            if element.id == 0x1F43B675 {
                let end = try Self.end(of: element, in: data)
                let range = element.payload.lowerBound..<end
                var clusterTime: UInt64?
                try Self.children(in: data, range: range) { child in
                    if child.id == 0xE7 { clusterTime = try Self.uint(in: data, range: child.payload) }
                }
                guard let clusterTime else { throw Self.invalidSize() }
                try Self.children(in: data, range: range) { child in
                    try Task.checkCancellation()
                    if child.id == 0xA3 {
                        count += try readBlock(child.payload, clusterTime: clusterTime,
                            frameDuration: frameDuration, consume: consume)
                    } else if child.id == 0xA0 {
                        var block: Range<Int>?
                        var codecState = false
                        try Self.children(in: data, range: child.payload) { groupChild in
                            if groupChild.id == 0xA1 { block = groupChild.payload }
                            if groupChild.id == 0xA4 { codecState = true }
                        }
                        if let block {
                            var start = block.lowerBound
                            let number = try Self.vint(in: data, at: &start, limit: block.upperBound).value
                            if number == track.number, codecState { throw MatroskaAudioError.unsupportedEncoding }
                            count += try readBlock(block, clusterTime: clusterTime,
                                frameDuration: frameDuration, consume: consume)
                        }
                    }
                }
                position = end
            } else {
                guard !element.unknown else { throw Self.invalidSize() }
                position = element.payload.upperBound
            }
        }
        guard count > 0 else { throw MatroskaAudioError.noAudio }
    }

    private func readBlock(
        _ range: Range<Int>, clusterTime: UInt64,
        frameDuration: (Data) throws -> Double, consume: (Data, Double) throws -> Void
    ) throws -> Int {
        var position = range.lowerBound
        let number = try Self.vint(in: data, at: &position, limit: range.upperBound).value
        guard number == track.number else { return 0 }
        guard range.upperBound - position >= 3 else { throw Self.invalidSize() }
        let relative = Int16(bitPattern: UInt16(data[position]) << 8 | UInt16(data[position + 1]))
        let flags = data[position + 2]
        position += 3
        let sizes = try Self.laceSizes(in: data, at: &position, limit: range.upperBound, mode: (flags >> 1) & 3)
        var timestamp = (Double(clusterTime) + Double(relative) * track.timestampScale)
            * timestampScale - track.codecDelay
        for size in sizes {
            try Task.checkCancellation()
            guard size > 0, size <= 16 * 1024 * 1024, size <= range.upperBound - position else {
                throw Self.invalidSize()
            }
            let frame = data.subdata(in: position..<(position + size))
            try consume(frame, timestamp)
            let duration = try track.defaultDuration ?? frameDuration(frame)
            guard duration.isFinite, duration > 0 else { throw Self.invalidSize() }
            timestamp += duration
            position += size
        }
        guard position == range.upperBound else { throw Self.invalidSize() }
        return sizes.count
    }

    static func laceSizes(in data: Data, at position: inout Int, limit: Int, mode: UInt8) throws -> [Int] {
        guard mode != 0 else { return [limit - position] }
        guard position < limit else { throw invalidSize() }
        let count = Int(data[position]) + 1
        position += 1
        guard count >= 2 else { throw invalidSize() }
        if mode == 2 {
            guard limit - position >= count, (limit - position) % count == 0 else { throw invalidSize() }
            return Array(repeating: (limit - position) / count, count: count)
        }
        var sizes: [Int] = []
        if mode == 1 {
            for _ in 0..<(count - 1) {
                var size = 0
                var byte: UInt8
                repeat {
                    guard position < limit else { throw invalidSize() }
                    byte = data[position]
                    position += 1
                    size += Int(byte)
                } while byte == 255
                sizes.append(size)
            }
        } else {
            let first = try vint(in: data, at: &position, limit: limit)
            guard first.value <= UInt64(limit - position) else { throw invalidSize() }
            sizes.append(Int(first.value))
            for _ in 1..<(count - 1) {
                let encoded = try vint(in: data, at: &position, limit: limit)
                let bias = (Int64(1) << (7 * encoded.length - 1)) - 1
                let size = Int64(sizes.last!) + Int64(encoded.value) - bias
                guard size > 0, size <= limit - position else { throw invalidSize() }
                sizes.append(Int(size))
            }
        }
        let used = sizes.reduce(0, +)
        guard sizes.allSatisfy({ $0 > 0 }), used < limit - position else { throw invalidSize() }
        sizes.append(limit - position - used)
        return sizes
    }

    private static func readTrack(in data: Data, range: Range<Int>) throws -> MatroskaAudioTrack {
        var track = MatroskaAudioTrack()
        try children(in: data, range: range) { child in
            switch child.id {
            case 0xD7: track.number = try uint(in: data, range: child.payload)
            case 0x83: track.type = try uint(in: data, range: child.payload)
            case 0xB9: track.enabled = try uint(in: data, range: child.payload) != 0
            case 0x86: track.codec = try string(in: data, range: child.payload)
            case 0x63A2:
                guard child.payload.count <= 1_048_576 else { throw invalidSize() }
                track.codecPrivate = data.subdata(in: child.payload)
            case 0x23E383:
                track.defaultDuration = Double(try uint(in: data, range: child.payload)) / 1_000_000_000
            case 0x23314F: track.timestampScale = try float(in: data, range: child.payload)
            case 0x56AA: track.codecDelay = Double(try uint(in: data, range: child.payload)) / 1_000_000_000
            case 0x6D80: track.hasContentEncoding = true
            case 0xE1:
                try children(in: data, range: child.payload) { audio in
                    switch audio.id {
                    case 0xB5: track.sampleRate = try float(in: data, range: audio.payload)
                    case 0x9F: track.channels = try uint(in: data, range: audio.payload)
                    case 0x6264: track.bitDepth = try uint(in: data, range: audio.payload)
                    default: break
                    }
                }
            default: break
            }
        }
        return track
    }

    private struct Element {
        var id: UInt64
        var payload: Range<Int>
        var unknown: Bool
    }

    private static func element(in data: Data, at position: inout Int, limit: Int) throws -> Element {
        let id = try vint(in: data, at: &position, limit: limit, retainingMarker: true)
        guard id.length <= 4 else { throw invalidSize() }
        let size = try vint(in: data, at: &position, limit: limit)
        let unknown = size.value == (UInt64(1) << (size.length * 7)) - 1
        guard unknown || size.value <= UInt64(limit - position) else { throw invalidSize() }
        return Element(id: id.value, payload: position..<(unknown ? limit : position + Int(size.value)), unknown: unknown)
    }

    private static func end(of element: Element, in data: Data) throws -> Int {
        guard element.unknown else { return element.payload.upperBound }
        guard element.id == 0x1F43B675 else { throw invalidSize() }
        var position = element.payload.lowerBound
        while position < element.payload.upperBound {
            try Task.checkCancellation()
            let start = position
            let child = try Self.element(in: data, at: &position, limit: element.payload.upperBound)
            if segmentLevelIDs.contains(child.id) { return start }
            guard !child.unknown else { throw invalidSize() }
            position = child.payload.upperBound
        }
        return position
    }

    private static func children(in data: Data, range: Range<Int>, visit: (Element) throws -> Void) throws {
        var position = range.lowerBound
        while position < range.upperBound {
            try Task.checkCancellation()
            let child = try element(in: data, at: &position, limit: range.upperBound)
            guard !child.unknown else { throw invalidSize() }
            try visit(child)
            position = child.payload.upperBound
        }
    }

    private static func vint(in data: Data, at position: inout Int, limit: Int,
        retainingMarker: Bool = false
    ) throws -> (value: UInt64, length: Int) {
        guard position >= 0, position < limit, limit <= data.count, data[position] != 0 else {
            throw invalidSize()
        }
        let first = data[position]
        let length = first.leadingZeroBitCount + 1
        guard length <= 8, length <= limit - position else { throw invalidSize() }
        var value = UInt64(retainingMarker ? first : first & (UInt8(0xFF) >> length))
        for index in 1..<length { value = value << 8 | UInt64(data[position + index]) }
        position += length
        return (value, length)
    }

    private static func uint(in data: Data, range: Range<Int>) throws -> UInt64 {
        guard (1...8).contains(range.count) else { throw invalidSize() }
        return range.reduce(UInt64(0)) { $0 << 8 | UInt64(data[$1]) }
    }

    private static func float(in data: Data, range: Range<Int>) throws -> Double {
        guard range.count == 4 || range.count == 8 else { throw invalidSize() }
        let bits = try uint(in: data, range: range)
        return range.count == 4 ? Double(Float(bitPattern: UInt32(bits))) : Double(bitPattern: bits)
    }

    private static func string(in data: Data, range: Range<Int>) throws -> String {
        guard range.count < 4096, let result = String(data: data.subdata(in: range), encoding: .utf8) else {
            throw invalidSize()
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
    }

    private static func invalidSize() -> MatroskaAudioError {
        .invalidFile("文件已损坏、被截断或包含无效的元素长度。")
    }
}
