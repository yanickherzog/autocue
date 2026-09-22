import Foundation

/// App-level audio-analysis defaults (SPEC.md §4.11), nested under
/// `Settings.audioAnalysisDefaults` rather than flat fields on `Settings` so
/// it can be passed directly to `DetectCuesUseCase`/`AudioAnalysisRepository`
/// without those APIs depending on the whole `Settings` type.
///
/// No `id` field — this is a plain configuration value, not an entity with
/// its own identity (`CLAUDE.md`, "Domain Model Value-Type Conformances").
public struct AnalysisSettings: Equatable, Hashable, Sendable {
    /// Default `.automatic` since 2026-09-10 (SPEC.md §4.11, "Threshold:
    /// manual vs. automatic"; `docs/DECISIONS.md`) — a fixed `.manual`
    /// threshold cannot serve both a normally-mixed file and a
    /// significantly quieter one (e.g. music mixed down as a background
    /// bed) with the same value, confirmed across four real gain tiers of
    /// the same content plus three genuinely distinct real pieces
    /// (choral, sustained/vibrato, electronic) with no defect found once
    /// the re-estimation sanity check (below) was in place.
    ///
    /// **`.automatic` mode's own calibration mechanism, Local Peak-Relative
    /// Calibration (LPRC), replaced the original fixed-cadence
    /// leading-window-minimum scheme entirely on 2026-09-22** (`docs/
    /// DECISIONS.md`) — that scheme's `calibrationMarginDb`/
    /// `noiseFloorReestimationIntervalSeconds` fields, and the implausible-
    /// jump sanity check they supported, are gone, not just renamed: they
    /// calibrated a *minimum* (a noise floor), which is exactly what
    /// pinned to `RMSWindowStream.epsilonClampDb` the moment a fixed-
    /// cadence leading window landed on genuine digital silence, and could
    /// then never legitimately recalibrate upward for the rest of the
    /// file. LPRC calibrates a *maximum* instead (`localPeakRadiusSeconds`/
    /// `activityMarginDb`, below) — immune to floor-pinning by
    /// construction, since a local maximum only reads near the epsilon
    /// floor when the entire local neighborhood genuinely is silent, which
    /// is exactly when that is the correct answer.
    public let noiseFloorCalibrationMode: NoiseFloorCalibrationMode
    public let silenceThresholdDb: Double
    /// `.automatic` mode only: half-width, in seconds, of the symmetric
    /// (backward *and* forward) window used to compute each measurement's
    /// local peak RMS-in-dBFS — `SilenceDetectionStage1` already operates
    /// on the full in-memory measurement array as a pure function, not a
    /// streaming stage, so nothing requires this to be causal/backward-only.
    /// See SPEC.md §4.11, "Local Peak-Relative Calibration."
    public let localPeakRadiusSeconds: Double
    /// `.automatic` mode only: the effective main threshold at time `t` is
    /// `localPeakDb(t) − activityMarginDb`, clamped to never fall below
    /// `RMSWindowStream.epsilonClampDb` (a local peak that has itself
    /// decayed to the epsilon floor means nothing real is nearby — true
    /// digital silence there must still always classify as silent).
    /// See SPEC.md §4.11, "Local Peak-Relative Calibration."
    public let activityMarginDb: Double
    /// `.automatic` mode only: replaces `minimumSilenceDurationSeconds` for
    /// LPRC's main-gap closure specifically — a floor-pinned-immune
    /// depth-relative threshold still can't, by itself, distinguish a real
    /// inter-cue gap from a brief-but-deep within-cue dip when both sit at
    /// a similar depth below their local peak; real duration data
    /// (`docs/DECISIONS.md`, 2026-09-22) shows the two are cleanly
    /// separated by *how long* the signal stays down, not by depth alone.
    /// `.manual` mode is untouched and keeps using
    /// `minimumSilenceDurationSeconds` exactly as before.
    public let automaticModeSilenceDurationSeconds: Double
    /// `.automatic` mode only: Minimum Audible Confirmation (`docs/
    /// DECISIONS.md`, 2026-09-22) — a coarse, region-level plausibility
    /// gate. A detected region is discarded unless it reaches this level
    /// somewhere within its own span, closing a narrow gap LPRC's
    /// depth-relative threshold alone leaves open: an isolated transient
    /// that never gets anywhere near audible (confirmed inaudible by direct
    /// listening on the real fixture that surfaced it, peaking at
    /// `-96.7dBFS`) can still register as a standalone region, because its
    /// own excursion contaminates its own local-peak reference.
    ///
    /// **Deliberately a separate field from `silenceThresholdDb`, not a
    /// reuse of it** — an earlier design draft proposed reusing
    /// `silenceThresholdDb` (`-40.0dBFS`) directly, on the reasoning that
    /// it was already validated as "clearly real vs. clearly not." Real
    /// validation caught this as wrong before it shipped: `-40.0dBFS` is
    /// exactly the fixed `.manual`-mode threshold `.automatic` mode's own
    /// default change (2026-09-10) exists specifically to beat — a real
    /// `-50dBFS` mixed-down cue, which `.automatic` mode must keep
    /// detecting, would itself never reach `-40dBFS` and would be wrongly
    /// discarded by this gate if it reused that value. `-80.0dBFS` sits
    /// with real margin below every legitimate quiet-cue level validated so
    /// far (`-50dBFS`) and with real margin above the one confirmed
    /// inaudible artifact this gate exists to catch (`-96.7dBFS`) — but
    /// this is, like `automaticModeSilenceDurationSeconds`, a
    /// real-but-thin two-point evidence band, not a wide, many-sample
    /// safety margin; re-validate if a future real fixture has a
    /// legitimate cue quieter than this or a spurious artifact louder than
    /// it. Applied only in `.automatic` mode — `.manual` mode is
    /// unaffected, including when configured with a custom, deep
    /// `silenceThresholdDb` that this fixed value could otherwise wrongly
    /// conflict with.
    public let minimumAudiblePeakDb: Double
    public let analysisWindowMilliseconds: Double
    /// How often a new RMS window is computed, independent of
    /// `analysisWindowMilliseconds` (the window's *length*) — windows
    /// overlap whenever this is smaller than the window length, as it is by
    /// default. Governs the time resolution at which threshold crossings can
    /// be located; must be ≤ `analysisWindowMilliseconds`. See SPEC.md
    /// §4.11, "RMS time resolution and threshold-crossing interpolation."
    public let analysisWindowHopMilliseconds: Double
    public let minimumSilenceDurationSeconds: Double
    public let minimumCueDurationSeconds: Double
    public let tailToleranceDb: Double
    /// **`.manual` mode: must stay strictly below `minimumSilenceDurationSeconds`.**
    /// The stricter-threshold branch this field gates can only start counting
    /// once the signal has *already* dropped below the deeper
    /// `silenceThresholdDb − tailToleranceDb` reference — which happens no
    /// earlier than the ordinary main-threshold gap started — so
    /// `stricterGapDuration ≤ mainGapDuration` holds at every instant, for
    /// every gap, by construction. If `tailCapSeconds ≥ minimumSilenceDurationSeconds`,
    /// the main-gap condition (`mainGapDuration ≥ minimumSilenceDurationSeconds`)
    /// always resolves at or before the stricter condition ever could, making
    /// this branch mathematically unreachable — confirmed both by this proof
    /// and, previously, by zero stricter-branch firings across a real
    /// multi-cue fixture file where several tails should have triggered it.
    /// See `docs/DECISIONS.md`, 2026-09-10.
    ///
    /// **`.automatic` mode reuses this same field for `tailCapSeconds`
    /// itself (the sustained-duration bar), but pairs it with
    /// `automaticModeTailToleranceDb` instead of this field for the depth
    /// margin** — see that field's doc comment for why `.automatic` mode
    /// needs a separately-derived tolerance, and why the shipped mechanism
    /// is a batch "earliest qualifying deep crossing within an
    /// already-confirmed-real run" rule (`AutomaticModeScanner`), not the
    /// real-time race `.manual` mode's `Stage1Scanner` still uses.
    public let tailCapSeconds: Double
    /// `.automatic` mode only (`docs/DECISIONS.md`, 2026-09-22) — the depth
    /// margin `AutomaticModeScanner` pairs with `tailCapSeconds` for its
    /// own stricter/tail-cap crossing, re-derived from `.manual`'s
    /// `tailToleranceDb` rather than reused: under LPRC, `mainThreshold` is
    /// already a deep, peak-relative value (`activityMarginDb`, `78.0`dB by
    /// default) rather than a shallow, near-ambient one, so "stricter"
    /// needs to mean something structurally different — `6.0`dB (the
    /// `.manual` default) barely moves the effective reference at all at
    /// that depth. `20.0`dB was chosen from real trajectory data as the
    /// value that let the stricter crossing meaningfully track into a real,
    /// long-lingering reverb tail (confirmed: TWBS cue8's real offset error
    /// went from `-8.205s` with this branch disabled to `-0.257s`) while
    /// structurally never firing on a real, sustained-but-brief within-cue
    /// dip regardless of its exact depth (Pass 1 of `AutomaticModeScanner`
    /// excludes those before depth is ever considered — see that type's
    /// doc comment). Confirmed safe across the full real fixture set at
    /// every value from `6.0` to `40.0`dB, not just at `20.0` — this
    /// specific value optimizes how much it helps genuine long tails, not
    /// whether it's safe.
    public let automaticModeTailToleranceDb: Double
    /// `.automatic` mode only (`docs/DECISIONS.md`, 2026-09-22) — bounds how
    /// far past the main-threshold crossing `AutomaticModeScanner` will
    /// search for a qualifying `automaticModeTailToleranceDb`-deep,
    /// `tailCapSeconds`-sustained crossing before giving up and using the
    /// main crossing directly. **Load-bearing, not a tuning nicety**: real
    /// trajectory data (TWBS cue5/cue8, ECHTE cue7/cue29) shows the main
    /// threshold's own crossing already lands within ~0-2s of the true
    /// perceptual end in every real case checked — large real overshoots
    /// (up to `+15.46s` on one real cue) came entirely from searching for a
    /// deep confirmation that, for a tail sitting on an extended
    /// quiet-but-not-silent plateau (real observed durations: `~5`-`16s`),
    /// never arrives until true digital silence. `0.5`s was chosen as the
    /// smallest value tested that still let every genuine fast/steep real
    /// decay (crossing both thresholds within ~1s) qualify unchanged, while
    /// making every observed long-plateau case correctly fall back to the
    /// already-accurate main crossing; `0.25`s produced identical results
    /// on the full real fixture set, so `0.5`s carries real margin, not a
    /// knife-edge value.
    public let automaticModeTailSearchBoundSeconds: Double
    public let embeddedMarkerMergeToleranceSeconds: Double
    /// Stage 2 only: how far, in seconds, before/after the stage-1
    /// candidate boundary the SuperFlux onset search looks. SPEC.md §4.11,
    /// "SuperFlux-based onset refinement."
    public let superFluxRefinementSearchWindowSeconds: Double
    /// Stage 2 only: how often a new STFT frame (and novelty-function
    /// value) is computed — the time resolution at which the refined
    /// boundary is ultimately reported. SPEC.md §4.11, "SuperFlux hop size
    /// and reported-boundary resolution."
    public let superFluxHopSeconds: Double
    /// Stage 2 only: width, in log-frequency filterbank bins, of the
    /// maximum filter applied across neighboring bins before computing the
    /// frame-to-frame novelty difference — the vibrato/tremolo-suppression
    /// mechanism. Must be odd. SPEC.md §4.11, "SuperFlux-based onset
    /// refinement."
    public let superFluxMaxFilterBandwidthBins: Int
    /// Stage 2 only: length, in seconds, of the local window used to
    /// compute the novelty function's local median for adaptive
    /// peak-picking. SPEC.md §4.11, "Adaptive local peak-picking."
    public let superFluxAdaptiveThresholdWindowSeconds: Double
    /// Stage 2 only: dimensionless multiplicative margin (`λ`) applied to
    /// the local median novelty value — the primary adaptive-sensitivity
    /// control. SPEC.md §4.11, "Adaptive local peak-picking."
    public let superFluxAdaptiveThresholdMultiplier: Double
    /// Stage 2 only: additive floor (`δ`), expressed as a fraction of the
    /// peak novelty value within the current search window — guards the
    /// near-silent-window edge case. SPEC.md §4.11, "Adaptive local
    /// peak-picking."
    public let superFluxAdaptiveThresholdOffset: Double

    public init(
        noiseFloorCalibrationMode: NoiseFloorCalibrationMode = .automatic,
        silenceThresholdDb: Double = -40.0,
        localPeakRadiusSeconds: Double = 30.0,
        activityMarginDb: Double = 78.0,
        automaticModeSilenceDurationSeconds: Double = 2.6,
        minimumAudiblePeakDb: Double = -80.0,
        analysisWindowMilliseconds: Double = 50.0,
        analysisWindowHopMilliseconds: Double = 10.0,
        minimumSilenceDurationSeconds: Double = 2.0,
        minimumCueDurationSeconds: Double = 3.0,
        tailToleranceDb: Double = 6.0,
        tailCapSeconds: Double = 0.5,
        automaticModeTailToleranceDb: Double = 20.0,
        automaticModeTailSearchBoundSeconds: Double = 0.5,
        embeddedMarkerMergeToleranceSeconds: Double = 1.0,
        superFluxRefinementSearchWindowSeconds: Double = 0.5,
        superFluxHopSeconds: Double = 0.01,
        superFluxMaxFilterBandwidthBins: Int = 3,
        superFluxAdaptiveThresholdWindowSeconds: Double = 0.1,
        superFluxAdaptiveThresholdMultiplier: Double = 1.5,
        superFluxAdaptiveThresholdOffset: Double = 0.05
    ) {
        self.noiseFloorCalibrationMode = noiseFloorCalibrationMode
        self.silenceThresholdDb = silenceThresholdDb
        self.localPeakRadiusSeconds = localPeakRadiusSeconds
        self.activityMarginDb = activityMarginDb
        self.automaticModeSilenceDurationSeconds = automaticModeSilenceDurationSeconds
        self.minimumAudiblePeakDb = minimumAudiblePeakDb
        self.analysisWindowMilliseconds = analysisWindowMilliseconds
        self.analysisWindowHopMilliseconds = analysisWindowHopMilliseconds
        self.minimumSilenceDurationSeconds = minimumSilenceDurationSeconds
        self.minimumCueDurationSeconds = minimumCueDurationSeconds
        self.tailToleranceDb = tailToleranceDb
        self.tailCapSeconds = tailCapSeconds
        self.automaticModeTailToleranceDb = automaticModeTailToleranceDb
        self.automaticModeTailSearchBoundSeconds = automaticModeTailSearchBoundSeconds
        self.embeddedMarkerMergeToleranceSeconds = embeddedMarkerMergeToleranceSeconds
        self.superFluxRefinementSearchWindowSeconds = superFluxRefinementSearchWindowSeconds
        self.superFluxHopSeconds = superFluxHopSeconds
        self.superFluxMaxFilterBandwidthBins = superFluxMaxFilterBandwidthBins
        self.superFluxAdaptiveThresholdWindowSeconds = superFluxAdaptiveThresholdWindowSeconds
        self.superFluxAdaptiveThresholdMultiplier = superFluxAdaptiveThresholdMultiplier
        self.superFluxAdaptiveThresholdOffset = superFluxAdaptiveThresholdOffset
    }
}

/// Whether `AnalysisSettings.silenceThresholdDb` is used directly, or
/// calibrated from the file's own measured noise floor (SPEC.md §4.11,
/// "Threshold: manual vs. automatic").
public enum NoiseFloorCalibrationMode: Equatable, Hashable, Sendable {
    case manual
    case automatic
}
