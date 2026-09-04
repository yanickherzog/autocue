import ACCore
import Foundation

/// Reads the RIFF sub-chunks `AVFoundation` doesn't expose (`CLAUDE.md`'s
/// Technology Stack table: "the custom parser reads `cue`/`labl`/`ltxt`/
/// `bext` chunks it doesn't expose") — a separate, lightweight, byte-level
/// walk of the file's chunk structure via `FileHandle`, distinct from
/// `AVAudioFile`'s PCM streaming (`WAVStreamingReader`). Never reads through
/// the (potentially huge) `data` chunk's contents — chunk sizes are used to
/// seek past it, so this has no memory-bound concern regardless of file size.
enum RIFFChunkParser {
    struct ParseResult: Equatable {
        let embeddedMarkers: [EmbeddedMarker]
        let broadcastWaveMetadata: BroadcastWaveMetadata?
    }

    /// Returns an empty result (never throws/crashes) for a WAV file with
    /// none of `cue`/`labl`/`ltxt`/`bext` present — per `ROADMAP.md` D8's
    /// Acceptance Criteria. Throws only for a file that isn't a valid RIFF/
    /// WAVE container at all.
    static func parse(url: URL) throws -> ParseResult {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        try validateRIFFWaveHeader(handle)

        var context = ParsingContext()
        while let header = try handle.readChunkHeader() {
            try processChunk(header, handle: handle, context: &context)
            try handle.skipPaddingByte(afterPayloadSize: Int(header.size))
        }
        return context.makeResult()
    }

    private static func validateRIFFWaveHeader(_ handle: FileHandle) throws {
        guard let riffTag = try handle.readExactly(4), asciiString(riffTag) == "RIFF" else {
            throw RIFFChunkParserError.notARIFFFile
        }
        _ = try handle.readExactly(4) // overall RIFF chunk size — unused, chunk-by-chunk sizes drive parsing
        guard let waveTag = try handle.readExactly(4), asciiString(waveTag) == "WAVE" else {
            throw RIFFChunkParserError.notAWAVEFile
        }
    }

    /// Only the small, structural chunks below are ever read into memory.
    /// Everything else — chiefly `data`, which can be multiple gigabytes —
    /// is skipped by seeking past its declared byte length, never read. This
    /// is what keeps this parser's own memory footprint independent of
    /// source file size, the same invariant `WAVStreamingReader`'s bounded
    /// chunks maintain for the sample data itself.
    private static func processChunk(
        _ header: (id: String, size: UInt32),
        handle: FileHandle,
        context: inout ParsingContext
    ) throws {
        switch header.id {
        case "fmt ":
            let payload = try handle.readExactly(Int(header.size)) ?? Data()
            context.sampleRate = FormatChunk.parseSampleRate(payload)
        case "cue ":
            let payload = try handle.readExactly(Int(header.size)) ?? Data()
            for cue in CueChunk.parse(payload) {
                context.cuePositionsByID[cue.id] = cue.sampleOffset
                context.cuePointOrder.append(cue.id)
            }
        case "LIST":
            let payload = try handle.readExactly(Int(header.size)) ?? Data()
            let (labels, notes) = ListAdtlChunk.parse(payload)
            context.labelsByID.merge(labels) { _, new in new }
            context.notesByID.merge(notes) { _, new in new }
        case "bext":
            let payload = try handle.readExactly(Int(header.size)) ?? Data()
            context.broadcastWaveMetadata = BroadcastWaveMetadataParser.parse(payload)
        default:
            try handle.skip(byteCount: Int(header.size))
        }
    }

    /// Decodes ASCII/UTF-8 chunk tags and text fields, tolerating invalid
    /// bytes (falls back to empty) rather than the non-failable
    /// `String(decoding:as:)`, which SwiftLint's `optional_data_string_conversion`
    /// flags in favor of this failable, explicit form.
    fileprivate static func asciiString(_ data: Data) -> String {
        String(bytes: data, encoding: .utf8) ?? ""
    }
}

/// Mutable accumulator for one `parse(url:)` pass — kept as its own type so
/// `processChunk` (above) can update it without `parse` itself growing past
/// SwiftLint's function-length threshold.
private struct ParsingContext {
    var sampleRate: Double = 0
    var cuePositionsByID: [UInt32: UInt32] = [:]
    var labelsByID: [UInt32: String] = [:]
    var notesByID: [UInt32: String] = [:]
    var broadcastWaveMetadata: BroadcastWaveMetadata?
    var cuePointOrder: [UInt32] = [] // preserves file order for stable output

    func makeResult() -> RIFFChunkParser.ParseResult {
        let markers = cuePointOrder.compactMap { id -> EmbeddedMarker? in
            guard let sampleOffset = cuePositionsByID[id] else { return nil }
            let offsetSeconds = sampleRate > 0 ? Double(sampleOffset) / sampleRate : 0
            return EmbeddedMarker(
                position: Timecode(offsetSeconds: offsetSeconds),
                label: labelsByID[id],
                note: notesByID[id]
            )
        }
        return RIFFChunkParser.ParseResult(embeddedMarkers: markers, broadcastWaveMetadata: broadcastWaveMetadata)
    }
}

enum RIFFChunkParserError: Error, Equatable {
    case notARIFFFile
    case notAWAVEFile
}

// MARK: - Individual chunk payload parsers

private enum FormatChunk {
    static func parseSampleRate(_ payload: Data) -> Double {
        guard payload.count >= 8 else { return 0 }
        // formatTag(2) + numChannels(2) + sampleRate(4) — sampleRate starts at byte 4.
        return Double(payload.readUInt32LittleEndian(at: 4))
    }
}

private enum CueChunk {
    struct CuePoint {
        let id: UInt32
        let sampleOffset: UInt32
    }

    /// Each cue point is a fixed 24 bytes: dwName(4), dwPosition(4),
    /// fccChunk(4), dwChunkStart(4), dwBlockStart(4), dwSampleOffset(4).
    static func parse(_ payload: Data) -> [CuePoint] {
        guard payload.count >= 4 else { return [] }
        let count = Int(payload.readUInt32LittleEndian(at: 0))
        var points: [CuePoint] = []
        points.reserveCapacity(count)
        for index in 0 ..< count {
            let base = 4 + index * 24
            guard base + 24 <= payload.count else { break }
            let id = payload.readUInt32LittleEndian(at: base)
            let sampleOffset = payload.readUInt32LittleEndian(at: base + 20)
            points.append(CuePoint(id: id, sampleOffset: sampleOffset))
        }
        return points
    }
}

private enum ListAdtlChunk {
    /// `LIST` payloads are typed by a leading 4-byte list-type tag (`adtl`
    /// for the associated-data-list this app cares about) followed by
    /// nested sub-chunks (`labl`/`ltxt`), each with its own even-byte
    /// padding rule, same as any RIFF chunk.
    static func parse(_ payload: Data) -> (labels: [UInt32: String], notes: [UInt32: String]) {
        guard payload.count >= 4, RIFFChunkParser.asciiString(payload.prefix(4)) == "adtl" else {
            return ([:], [:])
        }
        var labels: [UInt32: String] = [:]
        var notes: [UInt32: String] = [:]
        var offset = 4
        while offset + 8 <= payload.count {
            let idBytes = payload.subdata(in: (payload.startIndex + offset) ..< (payload.startIndex + offset + 4))
            let subChunkID = RIFFChunkParser.asciiString(idBytes)
            let subChunkSize = Int(payload.readUInt32LittleEndian(at: offset + 4))
            let subPayloadStart = offset + 8
            let subPayloadEnd = min(subPayloadStart + subChunkSize, payload.count)
            guard subPayloadStart <= payload.count else { break }
            let subPayload = payload.subdata(
                in: (payload.startIndex + subPayloadStart) ..< (payload.startIndex + subPayloadEnd)
            )

            switch subChunkID {
            case "labl":
                if let (id, text) = parseCuePointIDPrefixedString(subPayload) {
                    labels[id] = text
                }
            case "ltxt":
                if let (id, text) = parseLtxt(subPayload) {
                    notes[id] = text
                }
            default:
                break
            }

            offset = subPayloadStart + subChunkSize
            if subChunkSize % 2 != 0 {
                offset += 1
            } // even-byte chunk padding
        }
        return (labels, notes)
    }

    /// `labl`'s shape: cuePointID(4) + null-terminated text.
    private static func parseCuePointIDPrefixedString(_ payload: Data) -> (UInt32, String)? {
        guard payload.count >= 4 else { return nil }
        let id = payload.readUInt32LittleEndian(at: 0)
        let textBytes = payload.dropFirst(4).prefix { $0 != 0 }
        return (id, RIFFChunkParser.asciiString(textBytes))
    }

    /// `ltxt`'s shape: cuePointID(4), sampleLength(4), purposeID(4),
    /// country(2), language(2), dialect(2), codePage(2), [text].
    private static func parseLtxt(_ payload: Data) -> (UInt32, String)? {
        guard payload.count >= 20 else { return nil }
        let id = payload.readUInt32LittleEndian(at: 0)
        let textBytes = payload.dropFirst(20).prefix { $0 != 0 }
        return (id, RIFFChunkParser.asciiString(textBytes))
    }
}

// MARK: - Low-level byte helpers

private extension Data {
    func readUInt32LittleEndian(at offset: Int) -> UInt32 {
        let base = startIndex + offset
        guard base + 4 <= endIndex else { return 0 }
        return UInt32(self[base]) | (UInt32(self[base + 1]) << 8) | (UInt32(self[base + 2]) << 16) |
            (UInt32(self[base + 3]) << 24)
    }
}

private extension FileHandle {
    /// Reads exactly `count` bytes, or `nil` if fewer than `count` remain
    /// (end of file) — never a partial `Data` masquerading as a full read.
    func readExactly(_ count: Int) throws -> Data? {
        guard count > 0 else { return Data() }
        guard let data = try read(upToCount: count), data.count == count else { return nil }
        return data
    }

    /// Reads one RIFF chunk header (4-byte ASCII ID + 4-byte little-endian
    /// size), or `nil` at end of file.
    func readChunkHeader() throws -> (id: String, size: UInt32)? {
        guard let idBytes = try readExactly(4) else { return nil }
        guard let sizeBytes = try readExactly(4) else { return nil }
        let id = RIFFChunkParser.asciiString(idBytes)
        let size = sizeBytes.readUInt32LittleEndian(at: 0)
        return (id, size)
    }

    /// RIFF mandates every chunk payload be padded to an even byte count —
    /// `readChunkHeader`'s caller already consumed exactly `afterPayloadSize`
    /// payload bytes; this skips the one trailing pad byte if needed.
    func skipPaddingByte(afterPayloadSize size: Int) throws {
        if size % 2 != 0 {
            _ = try readExactly(1)
        }
    }

    /// Advances past `byteCount` bytes without reading them into memory —
    /// used for uninteresting chunks, chiefly `data`, which can be
    /// multi-gigabyte and must never be loaded whole.
    func skip(byteCount: Int) throws {
        guard byteCount > 0 else { return }
        let newOffset = try offset() + UInt64(byteCount)
        try seek(toOffset: newOffset)
    }
}
