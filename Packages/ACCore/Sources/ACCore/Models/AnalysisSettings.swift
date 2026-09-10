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
    public let noiseFloorCalibrationMode: NoiseFloorCalibrationMode
    public let silenceThresholdDb: Double
    public let calibrationMarginDb: Double
    public let noiseFloorReestimationIntervalSeconds: Double
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
    /// **Must stay strictly below `minimumSilenceDurationSeconds`.** The
    /// stricter-threshold branch this field gates can only start counting
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
    public let tailCapSeconds: Double
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
        calibrationMarginDb: Double = 6.0,
        noiseFloorReestimationIntervalSeconds: Double = 300.0,
        analysisWindowMilliseconds: Double = 50.0,
        analysisWindowHopMilliseconds: Double = 10.0,
        minimumSilenceDurationSeconds: Double = 2.0,
        minimumCueDurationSeconds: Double = 3.0,
        tailToleranceDb: Double = 6.0,
        tailCapSeconds: Double = 0.5,
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
        self.calibrationMarginDb = calibrationMarginDb
        self.noiseFloorReestimationIntervalSeconds = noiseFloorReestimationIntervalSeconds
        self.analysisWindowMilliseconds = analysisWindowMilliseconds
        self.analysisWindowHopMilliseconds = analysisWindowHopMilliseconds
        self.minimumSilenceDurationSeconds = minimumSilenceDurationSeconds
        self.minimumCueDurationSeconds = minimumCueDurationSeconds
        self.tailToleranceDb = tailToleranceDb
        self.tailCapSeconds = tailCapSeconds
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
