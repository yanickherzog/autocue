import AVFoundation
import Foundation

/// Streams a WAV file's PCM sample data in bounded, fixed-size chunks via
/// `AVAudioFile` — the one shared primitive every `ACAudioKit` consumer that
/// needs sample data reuses (`WaveformPeakExtractor`, `SilenceDetector`,
/// `AudioAnalysisRepositoryImpl.importAudio`'s own metadata read), rather
/// than each writing its own file-reading mechanism. Never loads a full file
/// into memory (`CLAUDE.md`, Performance Considerations) — every read is
/// bounded to `chunkFrameCount` frames.
///
/// Reports the *source* file's own format (sample rate, channel count, bit
/// depth) via `fileFormat` — distinct from `processingFormat`, the format
/// chunks are actually decoded into for downstream vDSP use (always Float32,
/// non-interleaved, regardless of the source's real bit depth). Conflating
/// the two is a common `AVAudioFile` mistake: `processingFormat` would
/// silently misreport every file as "32-bit" if used for `AudioAsset.bitDepth`.
public final class WAVStreamingReader {
    /// ~5.6s of stereo audio at 48kHz per chunk (256K frames × 2 channels ×
    /// 4 bytes/Float32 ≈ 2MB) — bounded well under any memory-pressure
    /// concern regardless of source file length, while still coarse enough
    /// to keep per-chunk vDSP call overhead low across a 3-hour file.
    public static let defaultChunkFrameCount: AVAudioFrameCount = 1 << 18

    private let audioFile: AVAudioFile

    public let sampleRate: Double
    public let channelCount: Int
    public let bitDepth: Int
    public let totalFrameCount: AVAudioFramePosition

    public var durationSeconds: Double {
        sampleRate > 0 ? Double(totalFrameCount) / sampleRate : 0
    }

    /// Opens `url` for streaming, requesting Float32/non-interleaved as the
    /// processing format up front (`AVAudioFile(forReading:commonFormat:
    /// interleaved:)`) — every chunk read through this instance comes back
    /// in that format, ready for vDSP, regardless of the source's own
    /// on-disk representation (16/24-bit int, 32-bit float, ...).
    public init(url: URL) throws {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        audioFile = file
        sampleRate = file.fileFormat.sampleRate
        channelCount = Int(file.fileFormat.channelCount)
        bitDepth = Int(file.fileFormat.streamDescription.pointee.mBitsPerChannel)
        totalFrameCount = file.length
    }

    /// Seeks the next `readNextChunk(maxFrameCount:)` call to start at
    /// `frame` — used both to restart a full-file pass and for a bounded
    /// time-range read (`generateWaveformDetail`, SuperFlux's search window).
    public func seek(toFrame frame: AVAudioFramePosition) {
        audioFile.framePosition = frame
    }

    /// Reads up to `maxFrameCount` frames starting at the reader's current
    /// position (see `seek(toFrame:)`), advancing the position past what was
    /// read. Returns `nil` once the end of the file has been reached — never
    /// an empty non-nil buffer, so callers can use `while let` directly.
    public func readNextChunk(
        maxFrameCount: AVAudioFrameCount = WAVStreamingReader.defaultChunkFrameCount
    ) throws -> AVAudioPCMBuffer? {
        guard audioFile.framePosition < totalFrameCount else { return nil }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: maxFrameCount) else {
            throw WAVStreamingReaderError.failedToAllocateBuffer
        }
        try audioFile.read(into: buffer, frameCount: maxFrameCount)
        guard buffer.frameLength > 0 else { return nil }
        return buffer
    }
}

public enum WAVStreamingReaderError: Error, Equatable {
    case failedToAllocateBuffer
}
