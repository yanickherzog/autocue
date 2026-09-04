/// One candidate non-silent region `SilenceDetector` found — a pair of
/// boundary instants, never a `Cue`. Merging against `AudioAsset.
/// embeddedMarkers` and constructing actual `Cue`s is `DetectCuesUseCase`'s
/// job (`ROADMAP.md` D9/T9.1, SPEC.md §4.11's "Combining with embedded
/// markers"), not this type's concern.
struct SilenceDetectedRegion: Equatable {
    /// The onset (silence→sound) boundary — refined by SuperFlux stage 2
    /// when a clear novelty peak is found within the search window,
    /// otherwise the stage-1 RMS crossing unchanged (SPEC.md §4.11's
    /// fallback rule).
    let startSeconds: Double
    /// The offset (sound→silence) boundary — governed entirely by stage 1's
    /// reverb-tail mechanism; never touched by SuperFlux (SPEC.md §4.11,
    /// "Why offset detection does not use SuperFlux...").
    let endSeconds: Double
}
