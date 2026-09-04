import Foundation

/// Constructs minimal, byte-exact, valid canonical WAV files programmatically
/// for `ACAudioKitTests` — including real `cue`/`labl`/`ltxt`/`bext`
/// sub-chunks for T8.2's marker-extraction tests. No binary WAV fixture is
/// committed to the repo; this is a self-documenting, generated-at-test-time
/// alternative, the same instinct `Audio_Analysis_Test/`'s own
/// plain-language-to-manifest workflow applies to real audio instead
/// (`ROADMAP.md` D8/T8.3).
///
/// Deliberately writes 16-bit PCM only — the most universally decodable WAV
/// variant, and this project has no float-PCM-specific requirement to test
/// against. Every chunk is written by hand at the byte level per the RIFF/BWF
/// specs (canonical `fmt `/`data`, the `cue `/`LIST adtl`/`labl`/`ltxt`
/// marker chunks, and the fixed 602-byte BWF `bext` header) — `AVFoundation`
/// doesn't expose a way to author these (`CLAUDE.md`'s Technology Stack
/// table), so there's no higher-level API to build fixtures with either.
enum WAVFixtureBuilder {
    /// One embedded cue point, mirroring the RIFF `cue`/`labl`/`ltxt` triple
    /// `RIFFChunkParser` (`ROADMAP.md` T8.2) must reassemble into one
    /// `ACCore.EmbeddedMarker`.
    struct CuePointFixture {
        let id: UInt32
        let sampleOffset: UInt32
        let label: String?
        let note: String?

        init(id: UInt32, sampleOffset: UInt32, label: String? = nil, note: String? = nil) {
            self.id = id
            self.sampleOffset = sampleOffset
            self.label = label
            self.note = note
        }
    }

    /// A subset of BWF `bext` fields worth round-tripping for the parser
    /// test — not every one of the format's 602 fixed bytes needs a fixture
    /// knob, only the ones `ACCore.BroadcastWaveMetadata` actually surfaces.
    struct BroadcastExtensionFixture {
        let description: String
        let originator: String
        let originatorReference: String
        let originationDate: String // "YYYY-MM-DD"
        let originationTime: String // "HH:MM:SS"
        let timeReferenceSamples: UInt64
    }

    /// Builds a complete WAV file's bytes.
    ///
    /// - Parameters:
    ///   - channelSamples: one `[Float]` array per channel (each `-1.0...1.0`,
    ///     same length across channels), converted internally to interleaved
    ///     16-bit PCM.
    static func makeWAVData(
        sampleRate: Double = 48000,
        channelSamples: [[Float]],
        cuePoints: [CuePointFixture] = [],
        broadcastExtension: BroadcastExtensionFixture? = nil
    ) -> Data {
        let channelCount = channelSamples.count
        let frameCount = channelSamples.first?.count ?? 0
        let bitsPerSample: UInt16 = 16
        let blockAlign = UInt16(channelCount) * (bitsPerSample / 8)
        let byteRate = UInt32(sampleRate) * UInt32(blockAlign)

        var dataChunkPayload = Data(capacity: frameCount * Int(blockAlign))
        for frame in 0 ..< frameCount {
            for channel in 0 ..< channelCount {
                let clamped = max(-1.0, min(1.0, channelSamples[channel][frame]))
                let intSample = Int16(clamped * Float(Int16.max))
                dataChunkPayload.appendLittleEndian(intSample)
            }
        }

        var fmtPayload = Data()
        fmtPayload.appendLittleEndian(UInt16(1)) // PCM
        fmtPayload.appendLittleEndian(UInt16(channelCount))
        fmtPayload.appendLittleEndian(UInt32(sampleRate))
        fmtPayload.appendLittleEndian(byteRate)
        fmtPayload.appendLittleEndian(blockAlign)
        fmtPayload.appendLittleEndian(bitsPerSample)

        var subChunks: [Data] = [
            riffSubChunk(id: "fmt ", payload: fmtPayload),
        ]

        if let broadcastExtension {
            subChunks.append(riffSubChunk(id: "bext", payload: bextPayload(broadcastExtension)))
        }

        if !cuePoints.isEmpty {
            subChunks.append(riffSubChunk(id: "cue ", payload: cueChunkPayload(cuePoints)))
            subChunks.append(listAdtlChunk(cuePoints))
        }

        subChunks.append(riffSubChunk(id: "data", payload: dataChunkPayload))

        var riffPayload = Data()
        riffPayload.append(contentsOf: Array("WAVE".utf8))
        for chunk in subChunks {
            riffPayload.append(chunk)
        }

        var file = Data()
        file.append(contentsOf: Array("RIFF".utf8))
        file.appendLittleEndian(UInt32(riffPayload.count))
        file.append(riffPayload)
        return file
    }

    @discardableResult
    static func writeWAVFile(
        sampleRate: Double = 48000,
        channelSamples: [[Float]],
        cuePoints: [CuePointFixture] = [],
        broadcastExtension: BroadcastExtensionFixture? = nil,
        to url: URL
    ) throws -> URL {
        let data = makeWAVData(
            sampleRate: sampleRate,
            channelSamples: channelSamples,
            cuePoints: cuePoints,
            broadcastExtension: broadcastExtension
        )
        try data.write(to: url)
        return url
    }

    /// A fresh temp-directory URL for one test's fixture file — callers are
    /// responsible for cleanup (`addTeardownBlock` or `FileManager.removeItem`),
    /// same as any other test-owned temp file in this codebase.
    static func makeTemporaryURL(filename: String = "\(UUID().uuidString).wav") -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    }

    // MARK: - Chunk builders

    private static func riffSubChunk(id: String, payload: Data) -> Data {
        var chunk = Data()
        chunk.append(contentsOf: Array(id.utf8))
        chunk.appendLittleEndian(UInt32(payload.count))
        chunk.append(payload)
        if payload.count % 2 != 0 {
            chunk.append(0) // RIFF mandates even-byte chunk padding
        }
        return chunk
    }

    private static func cueChunkPayload(_ cuePoints: [CuePointFixture]) -> Data {
        var payload = Data()
        payload.appendLittleEndian(UInt32(cuePoints.count))
        for cue in cuePoints {
            payload.appendLittleEndian(cue.id) // dwName
            payload.appendLittleEndian(cue.sampleOffset) // dwPosition (play-order position)
            payload.append(contentsOf: Array("data".utf8)) // fccChunk
            payload.appendLittleEndian(UInt32(0)) // dwChunkStart
            payload.appendLittleEndian(UInt32(0)) // dwBlockStart
            payload.appendLittleEndian(cue.sampleOffset) // dwSampleOffset
        }
        return payload
    }

    private static func listAdtlChunk(_ cuePoints: [CuePointFixture]) -> Data {
        var adtlPayload = Data()
        adtlPayload.append(contentsOf: Array("adtl".utf8))
        for cue in cuePoints {
            if let label = cue.label {
                adtlPayload.append(riffSubChunk(id: "labl", payload: nullTerminated(label, cuePointID: cue.id)))
            }
            if let note = cue.note {
                var ltxtPayload = Data()
                ltxtPayload.appendLittleEndian(cue.id)
                ltxtPayload.appendLittleEndian(UInt32(0)) // dwSampleLength
                ltxtPayload.append(contentsOf: Array("rgn ".utf8)) // dwPurposeID
                ltxtPayload.appendLittleEndian(UInt16(0)) // wCountry
                ltxtPayload.appendLittleEndian(UInt16(0)) // wLanguage
                ltxtPayload.appendLittleEndian(UInt16(0)) // wDialect
                ltxtPayload.appendLittleEndian(UInt16(0)) // wCodePage
                ltxtPayload.append(contentsOf: Array(note.utf8))
                adtlPayload.append(riffSubChunk(id: "ltxt", payload: ltxtPayload))
            }
        }
        return riffSubChunk(id: "LIST", payload: adtlPayload)
    }

    private static func nullTerminated(_ text: String, cuePointID: UInt32) -> Data {
        var payload = Data()
        payload.appendLittleEndian(cuePointID)
        payload.append(contentsOf: Array(text.utf8))
        payload.append(0)
        return payload
    }

    private static func bextPayload(_ fixture: BroadcastExtensionFixture) -> Data {
        var payload = Data()
        payload.append(fixedWidthASCII(fixture.description, width: 256))
        payload.append(fixedWidthASCII(fixture.originator, width: 32))
        payload.append(fixedWidthASCII(fixture.originatorReference, width: 32))
        payload.append(fixedWidthASCII(fixture.originationDate, width: 10))
        payload.append(fixedWidthASCII(fixture.originationTime, width: 8))
        payload.appendLittleEndian(UInt32(truncatingIfNeeded: fixture.timeReferenceSamples & 0xFFFF_FFFF)) // low
        payload.appendLittleEndian(UInt32(truncatingIfNeeded: fixture.timeReferenceSamples >> 32)) // high
        payload.appendLittleEndian(UInt16(1)) // version
        payload.append(Data(count: 64)) // UMID
        payload.append(Data(count: 2)) // loudness value
        payload.append(Data(count: 2)) // loudness range
        payload.append(Data(count: 2)) // max true peak
        payload.append(Data(count: 2)) // max momentary loudness
        payload.append(Data(count: 2)) // max short-term loudness
        payload.append(Data(count: 180)) // reserved
        return payload
    }

    private static func fixedWidthASCII(_ string: String, width: Int) -> Data {
        var bytes = Array(string.utf8.prefix(width))
        while bytes.count < width {
            bytes.append(0)
        }
        return Data(bytes)
    }
}

private extension Data {
    mutating func appendLittleEndian(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }

    mutating func appendLittleEndian(_ value: Int16) {
        appendLittleEndian(UInt16(bitPattern: value))
    }
}
