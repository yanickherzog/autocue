import Accelerate
import AVFoundation

/// Sums a multi-channel deinterleaved buffer's channels into a mono trace,
/// scaled by `1/channelCount` (SPEC.md §4.15's "v1 simplification: mono
/// mixdown, not per-channel," applied consistently everywhere this project
/// reduces multi-channel audio to one trace — `WaveformPeakExtractor` and
/// `SilenceDetector` both need it, so it's factored out once rather than
/// duplicated a second time, per `CLAUDE.md` rule 7).
enum MonoMixdown {
    static func mixdown(
        channelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        channelCount: Int,
        frameLength: Int,
        into destination: UnsafeMutableBufferPointer<Float>
    ) {
        guard let destBase = destination.baseAddress else { return }
        vDSP_vclr(destBase, 1, vDSP_Length(frameLength))
        for channel in 0 ..< channelCount {
            vDSP_vadd(destBase, 1, channelData[channel], 1, destBase, 1, vDSP_Length(frameLength))
        }
        var scale = Float(1.0 / Double(channelCount))
        vDSP_vsmul(destBase, 1, &scale, destBase, 1, vDSP_Length(frameLength))
    }
}
