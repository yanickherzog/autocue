import ACCore
import ACDesignSystem
import Foundation

/// Maps `cues` (`ACCore`) to `CueTableView`'s domain-free `CueTableRow`
/// adapter (`ACDesignSystem`) — split into its own file purely to stay under
/// this project's type-body-length lint limit, same reason
/// `+BoundaryDragging.swift`/`+Delete.swift` are already separate.
extension CueDetectionReviewViewModel {
    /// SPEC.md §4.3's TC In/TC Out/Length display rules, applied here — the
    /// only place `Cue.startTimecode`/`.duration` get formatted for
    /// `CueTableView`. TC In/TC Out both fall back to the shared `"—"`
    /// placeholder when `startTimecode` is `nil`; Length never needs one
    /// (`Cue.duration` is never optional).
    ///
    /// **`Setup.timecodeStart` is added before formatting, not `cue.startTimecode`
    /// alone.** `Cue.startTimecode` stays audio-file-relative everywhere else
    /// in this ViewModel (waveform markers, playback, drag/split/merge math)
    /// — it has to, since that's the coordinate system the waveform view and
    /// `AudioPlaybackController` actually operate in. TC In/TC Out are the
    /// one place a cue's position is shown to a human as the film's own
    /// absolute timecode, so `timecodeStart`'s offset is added here, at the
    /// point of display, and nowhere else. See SPEC.md §4.3.
    public var tableRows: [CueTableRow] {
        let startOffset = timecodeStart?.offsetSeconds ?? 0
        return cues.enumerated().map { index, cue in
            let tcIn: String
            let tcOut: String
            if let start = cue.startTimecode {
                let displayStart = Timecode(offsetSeconds: startOffset + start.offsetSeconds)
                tcIn = displayStart.formatted(at: timecodeFrameRate)
                let displayEnd = Timecode(offsetSeconds: displayStart.offsetSeconds + cue.duration.seconds)
                tcOut = displayEnd.formatted(at: timecodeFrameRate)
            } else {
                tcIn = Self.noTimecodePlaceholder
                tcOut = Self.noTimecodePlaceholder
            }
            return CueTableRow(
                id: index,
                number: index + 1,
                title: cue.title,
                tcIn: tcIn,
                tcOut: tcOut,
                length: Self.formattedLength(cue.duration)
            )
        }
    }

    private static let noTimecodePlaceholder = "—"

    /// `MM:SS` — a deliberate exception to `MediaDuration.formatted`'s
    /// general `HH:MM:SS`, scoped specifically to this cue-sheet display
    /// context (SPEC.md §4.3: a single cue's usage duration realistically
    /// never runs past an hour, unlike `Setup.totalMusicRuntime`).
    private static func formattedLength(_ duration: MediaDuration) -> String {
        let totalSeconds = Int(duration.seconds.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
