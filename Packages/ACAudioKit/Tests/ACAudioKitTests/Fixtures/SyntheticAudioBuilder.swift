import Foundation

/// Generates synthetic mono `[Float]` sample buffers for
/// `SilenceDetectorTests` — clean transitions, fades, vibrato modulation,
/// and mixed loud/quiet passages — entirely in memory, no file I/O
/// (`SilenceDetector`'s pure `detectRegions(monoSamples:...)` entry point
/// takes these directly).
enum SyntheticAudioBuilder {
    static func silence(seconds: Double, sampleRate: Double) -> [Float] {
        [Float](repeating: 0, count: frameCount(seconds: seconds, sampleRate: sampleRate))
    }

    static func tone(
        seconds: Double,
        sampleRate: Double,
        frequency: Double = 440,
        amplitude: Float
    ) -> [Float] {
        let count = frameCount(seconds: seconds, sampleRate: sampleRate)
        // Reduces `index` modulo the period length *before* multiplying by
        // frequency, keeping the `sin()` argument bounded in [0, 2π)
        // regardless of how large `index` grows — computing
        // `sin(2π·f·index/sampleRate)` directly loses phase precision for
        // large `index` (the argument itself grows without bound, so a
        // `Double`'s fixed relative precision translates into growing
        // *absolute* phase error over a long buffer), which would make a
        // supposedly perfectly-periodic tone drift out of exact
        // self-similarity late in a long buffer — a real, previously-hit
        // artifact, not a hypothetical one (see `SilenceDetectorTests`'
        // steady-tone fallback test, which depends on this generator being
        // genuinely, exactly periodic throughout).
        let samplesPerPeriod = sampleRate / frequency
        return (0 ..< count).map { index in
            let reducedIndex = Double(index).truncatingRemainder(dividingBy: samplesPerPeriod)
            let phase = 2 * Double.pi * reducedIndex / samplesPerPeriod
            return amplitude * Float(sin(phase))
        }
    }

    /// A tone that ramps from silence to `amplitude` over the whole
    /// segment, front-loaded (cubic ease-out: `1 - (1-t)³`) rather than
    /// linear — the realistic shape of a musical attack that rises quickly
    /// at first and levels off, not a constant-rate ramp. This matters for
    /// what it's used to test: a flux-based novelty function responds to
    /// the *rate* of energy increase, which is highest early in this shape
    /// (close to the true onset) and decreasing thereafter — a linear ramp,
    /// by contrast, has energy accelerating (amplitude² grows faster later
    /// in the ramp), which would bias any flux-based peak *later*, the
    /// opposite of the real-world case this fixture exists to model.
    static func fadeIn(
        seconds: Double,
        sampleRate: Double,
        frequency: Double = 440,
        amplitude: Float
    ) -> [Float] {
        let count = frameCount(seconds: seconds, sampleRate: sampleRate)
        return (0 ..< count).map { index in
            let progress = Double(index) / Double(max(count - 1, 1))
            let envelope = Float(1 - pow(1 - progress, 3))
            return envelope * amplitude * Float(sin(2 * .pi * frequency * Double(index) / sampleRate))
        }
    }

    /// A steady tone with no meaningful spectral change — used to prove
    /// stage 2 falls back to the stage-1 boundary when no clear novelty
    /// peak exists (a flat-spectrum control, distinct from the vibrato case
    /// below, which has *some* spectral wobble but no genuine re-attack).
    static func flatSpectrumTone(
        seconds: Double,
        sampleRate: Double,
        frequency: Double = 440,
        amplitude: Float
    ) -> [Float] {
        tone(seconds: seconds, sampleRate: sampleRate, frequency: frequency, amplitude: amplitude)
    }

    /// A sustained tone with vibrato (frequency modulation) — natural
    /// pitch wobble on an otherwise-continuous note, no genuine re-attack.
    /// This is exactly the false-positive case SuperFlux's max-filter step
    /// exists to suppress.
    static func vibratoTone(
        seconds: Double,
        sampleRate: Double,
        baseFrequency: Double = 440,
        amplitude: Float,
        vibratoRateHz: Double = 6,
        vibratoDepthHz: Double = 15
    ) -> [Float] {
        let count = frameCount(seconds: seconds, sampleRate: sampleRate)
        var phase = 0.0
        var samples = [Float](repeating: 0, count: count)
        for index in 0 ..< count {
            let time = Double(index) / sampleRate
            let instantaneousFrequency = baseFrequency + vibratoDepthHz * sin(2 * .pi * vibratoRateHz * time)
            phase += 2 * .pi * instantaneousFrequency / sampleRate
            samples[index] = amplitude * Float(sin(phase))
        }
        return samples
    }

    static func concatenate(_ segments: [[Float]]) -> [Float] {
        segments.flatMap { $0 }
    }

    /// Converts a target RMS level in dBFS to the peak amplitude of a sine
    /// tone that produces it (`rms = amplitude / √2` for a pure sine).
    static func amplitude(forRMSDb db: Double) -> Float {
        let rms = pow(10.0, db / 20.0)
        return Float(rms * 2.0.squareRoot())
    }

    private static func frameCount(seconds: Double, sampleRate: Double) -> Int {
        max(0, Int(seconds * sampleRate))
    }
}
