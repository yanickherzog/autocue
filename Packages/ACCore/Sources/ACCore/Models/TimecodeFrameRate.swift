import Foundation

/// The display frame rate used to format/parse a `Timecode` as `HH:MM:SS:FF`.
///
/// This is never derived from audio metadata — a WAV file carries no video frame
/// rate. It's a per-production, user-configurable display convention
/// (`Setup.timecodeFrameRate`, SPEC.md §4.2/§4.9), independent of the underlying
/// `Timecode.offsetSeconds` it's used to format.
public enum TimecodeFrameRate: Equatable, Hashable, CaseIterable, Sendable {
    case fps24
    case fps25
    case fps29_97NonDrop
    case fps29_97Drop
    case fps30

    /// The modulus used for the `FF` field and for hour/minute/second decomposition.
    public var nominalFramesPerSecond: Int {
        switch self {
        case .fps24: 24
        case .fps25: 25
        case .fps29_97NonDrop, .fps29_97Drop: 30
        case .fps30: 30
        }
    }

    /// The real (non-integer, where applicable) frame rate used to convert a time
    /// offset to a frame count.
    public var realFramesPerSecond: Double {
        switch self {
        case .fps24: 24.0
        case .fps25: 25.0
        case .fps29_97NonDrop, .fps29_97Drop: 29.97
        case .fps30: 30.0
        }
    }

    /// Whether this frame rate uses SMPTE drop-frame numbering (skips frame
    /// numbers 0 and 1 at the start of every minute except every 10th minute).
    ///
    /// Only `.fps29_97Drop` is drop-frame. `.fps24`, `.fps25`, and `.fps30` have
    /// no real/nominal mismatch to correct for, so drop-frame numbering doesn't
    /// apply to them — see SPEC.md §4.9.
    public var isDropFrame: Bool {
        self == .fps29_97Drop
    }

    /// Number of display frame-numbers skipped per non-exempt minute, for
    /// drop-frame rates. SMPTE's general rule: `round(nominalFPS × 0.0666...)`,
    /// i.e. `nominalFPS / 15` — 2 for 30fps-nominal, 4 for a hypothetical
    /// 60fps-nominal drop-frame rate. Meaningless (and unused) for non-drop rates.
    var dropFramesPerNonExemptMinute: Int {
        nominalFramesPerSecond / 15
    }
}
