import Foundation

/// An absolute **position** within an `AudioAsset` — an offset from the start of
/// the file. Contrast with `MediaDuration`, a *length*.
///
/// `Timecode` itself is frame-rate-agnostic: it stores nothing but a precise time
/// offset. Formatting that offset as `HH:MM:SS:FF` (including whether drop-frame
/// numbering applies) always requires an explicit `TimecodeFrameRate` argument —
/// see SPEC.md §4.9. Don't add a stored frame rate to this type.
public struct Timecode: Equatable, Hashable, Comparable, Sendable {
    public let offsetSeconds: Double

    public init(offsetSeconds: Double) {
        precondition(offsetSeconds >= 0, "Timecode.offsetSeconds must be non-negative")
        self.offsetSeconds = offsetSeconds
    }

    public static func < (lhs: Timecode, rhs: Timecode) -> Bool {
        lhs.offsetSeconds < rhs.offsetSeconds
    }
}

/// The decomposed `HH:MM:SS:FF` fields of a `Timecode` under a specific
/// `TimecodeFrameRate`. Not stored anywhere — always computed on demand from
/// `Timecode.offsetSeconds`, so changing `Setup.timecodeFrameRate` later never
/// requires migrating existing data (SPEC.md §4.9).
public struct TimecodeComponents: Equatable, Hashable, Sendable {
    public let hours: Int
    public let minutes: Int
    public let seconds: Int
    public let frames: Int

    public init(hours: Int, minutes: Int, seconds: Int, frames: Int) {
        self.hours = hours
        self.minutes = minutes
        self.seconds = seconds
        self.frames = frames
    }
}

extension Timecode {

    /// Decomposes this position into `HH:MM:SS:FF` fields under `frameRate`.
    ///
    /// Non-drop-frame rates: `totalFrames = round(offsetSeconds × realFPS)`,
    /// then a plain base-`nominalFPS` decomposition.
    ///
    /// Drop-frame (`.fps29_97Drop`): the real frame count is first converted to
    /// a *display* frame number via SMPTE drop-frame numbering — frame numbers
    /// 0 and 1 are skipped at the start of every minute except every 10th
    /// minute — and *that* is what gets decomposed. This is what keeps drop-frame
    /// timecode aligned with wall-clock time at hour boundaries despite 29.97fps
    /// running slightly slower than nominal 30fps.
    public func components(at frameRate: TimecodeFrameRate) -> TimecodeComponents {
        let realFrameCount = Int((offsetSeconds * frameRate.realFramesPerSecond).rounded())
        let displayFrameNumber = frameRate.isDropFrame
            ? Self.dropFrameDisplayNumber(realFrameCount: realFrameCount, frameRate: frameRate)
            : realFrameCount

        let nominal = frameRate.nominalFramesPerSecond
        let frames = displayFrameNumber % nominal
        let totalSeconds = displayFrameNumber / nominal
        let seconds = totalSeconds % 60
        let totalMinutes = totalSeconds / 60
        let minutes = totalMinutes % 60
        let hours = totalMinutes / 60

        return TimecodeComponents(hours: hours, minutes: minutes, seconds: seconds, frames: frames)
    }

    /// `HH:MM:SS:FF`, zero-padded. Drop-frame timecode conventionally uses a
    /// `;` separator before the frame field instead of `:` — applied here.
    public func formatted(at frameRate: TimecodeFrameRate) -> String {
        let c = components(at: frameRate)
        let frameSeparator = frameRate.isDropFrame ? ";" : ":"
        return String(format: "%02d:%02d:%02d%@%02d", c.hours, c.minutes, c.seconds, frameSeparator, c.frames)
    }

    /// Reconstructs the underlying offset from `HH:MM:SS:FF` components under
    /// `frameRate` — the inverse of `components(at:)`.
    ///
    /// Returns `nil` for out-of-range fields, or (drop-frame only) for a frame
    /// number that doesn't exist under drop-frame numbering — `FF` of 0 or 1 at
    /// `SS == 0` of a non-exempt minute (SPEC.md §4.9). Silently accepting those
    /// would produce a `Timecode` that round-trips to a *different* displayed
    /// string than what was typed in, which is worse than rejecting it outright.
    public init?(components: TimecodeComponents, frameRate: TimecodeFrameRate) {
        let nominal = frameRate.nominalFramesPerSecond
        guard components.frames >= 0, components.frames < nominal,
              components.seconds >= 0, components.seconds < 60,
              components.minutes >= 0, components.minutes < 60,
              components.hours >= 0
        else {
            return nil
        }

        let totalMinutes = components.hours * 60 + components.minutes

        if frameRate.isDropFrame {
            let isExemptMinute = totalMinutes % 10 == 0
            let dropped = frameRate.dropFramesPerNonExemptMinute
            if components.seconds == 0, !isExemptMinute, components.frames < dropped {
                return nil
            }
        }

        let displayFrameNumber = components.frames
            + nominal * (components.seconds + 60 * (components.minutes + 60 * components.hours))

        let realFrameCount: Int
        if frameRate.isDropFrame {
            let dropped = frameRate.dropFramesPerNonExemptMinute
            let nonExemptMinutesElapsed = totalMinutes - totalMinutes / 10
            realFrameCount = displayFrameNumber - dropped * nonExemptMinutesElapsed
        } else {
            realFrameCount = displayFrameNumber
        }

        self.init(offsetSeconds: Double(realFrameCount) / frameRate.realFramesPerSecond)
    }

    /// SMPTE drop-frame numbering: converts a real (uncorrected) frame count
    /// into the *display* frame number drop-frame timecode would show — i.e.
    /// re-inserts the 2 frame-numbers skipped at the start of every minute
    /// except every 10th, so the subsequent plain base-`nominalFPS` decomposition
    /// lands on the correct drop-frame reading.
    private static func dropFrameDisplayNumber(realFrameCount: Int, frameRate: TimecodeFrameRate) -> Int {
        let dropped = frameRate.dropFramesPerNonExemptMinute            // 2, for 30fps-nominal
        let framesPerMinuteNominal = frameRate.nominalFramesPerSecond * 60   // 1800
        let framesPerMinuteDropAdjusted = framesPerMinuteNominal - dropped  // 1798
        let framesPer10MinDropAdjusted = framesPerMinuteNominal * 10 - dropped * 9  // 17982

        let tenMinuteBlocks = realFrameCount / framesPer10MinDropAdjusted
        let remainder = realFrameCount % framesPer10MinDropAdjusted

        if remainder < dropped {
            return realFrameCount + dropped * 9 * tenMinuteBlocks
        } else {
            let minutesIntoBlock = (remainder - dropped) / framesPerMinuteDropAdjusted
            return realFrameCount + dropped * 9 * tenMinuteBlocks + dropped * minutesIntoBlock
        }
    }
}
