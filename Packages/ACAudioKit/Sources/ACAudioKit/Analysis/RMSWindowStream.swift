import Accelerate
import Foundation

/// One windowed-RMS-in-dBFS measurement, centered at `windowCenterSeconds`
/// (SPEC.md §4.11).
struct RMSWindowMeasurement: Equatable {
    let windowCenterSeconds: Double
    let rmsDb: Double
}

/// Computes overlapping windowed-RMS-in-dBFS measurements incrementally as
/// mono sample chunks arrive — the streaming half of SPEC.md §4.11's "RMS
/// time resolution" contract (hop decoupled from window length, windows
/// overlapping by default).
///
/// **Bounded memory, independent of source file length:** only ever holds a
/// small look-back buffer (at most one window's worth of samples) between
/// `ingest` calls, never the whole file — this is what lets stage 1 process
/// a 3-hour file without ever materializing its raw samples in one array.
/// The *output* (one small `RMSWindowMeasurement` per hop) is cheap enough
/// to accumulate in full for an entire file — a 3-hour file at the `10`ms
/// hop default produces ~1.08M measurements, each 16 bytes ≈ 17MB, trivial
/// compared to holding raw samples — so everything *downstream* of this type
/// (`SilenceDetectionStage1`) operates on that full, already-reduced
/// measurement array as a plain in-memory value, not as a second streaming
/// stage.
struct RMSWindowStream {
    let sampleRate: Double
    let windowFrameCount: Int
    let hopFrameCount: Int

    private var pending: [Float] = []
    private var pendingGlobalStart = 0
    private var nextWindowGlobalStart = 0

    init(sampleRate: Double, windowFrameCount: Int, hopFrameCount: Int) {
        self.sampleRate = sampleRate
        self.windowFrameCount = max(windowFrameCount, 1)
        self.hopFrameCount = max(hopFrameCount, 1)
    }

    /// Feeds the next chunk of mono samples (in file order, contiguous with
    /// whatever was last ingested) and returns every fully-computed window
    /// this chunk completed. A window that straddles two chunks is handled
    /// automatically via the internal look-back buffer — callers never need
    /// to align chunk boundaries to window/hop boundaries themselves.
    mutating func ingest(monoSamples: UnsafeBufferPointer<Float>) -> [RMSWindowMeasurement] {
        pending.append(contentsOf: monoSamples)

        var results: [RMSWindowMeasurement] = []
        while nextWindowGlobalStart + windowFrameCount <= pendingGlobalStart + pending.count {
            let localStart = nextWindowGlobalStart - pendingGlobalStart
            var rms: Float = 0
            pending.withUnsafeBufferPointer { pointer in
                guard let base = pointer.baseAddress else { return }
                vDSP_rmsqv(base + localStart, 1, &rms, vDSP_Length(windowFrameCount))
            }
            let db = 20 * log10(max(Double(rms), 1e-9))
            let centerGlobal = Double(nextWindowGlobalStart) + Double(windowFrameCount) / 2.0
            results.append(RMSWindowMeasurement(windowCenterSeconds: centerGlobal / sampleRate, rmsDb: db))
            nextWindowGlobalStart += hopFrameCount
        }

        let dropCount = min(max(nextWindowGlobalStart - pendingGlobalStart, 0), pending.count)
        if dropCount > 0 {
            pending.removeFirst(dropCount)
            pendingGlobalStart += dropCount
        }

        return results
    }
}
