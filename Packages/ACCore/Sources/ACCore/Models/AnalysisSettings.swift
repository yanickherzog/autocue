import Foundation

/// App-level audio-analysis defaults (SPEC.md §4.11), nested under
/// `Settings.audioAnalysisDefaults` rather than flat fields on `Settings` so
/// it can be passed directly to `DetectCuesUseCase`/`AudioAnalysisRepository`
/// without those APIs depending on the whole `Settings` type.
///
/// No `id` field — this is a plain configuration value, not an entity with
/// its own identity (`CLAUDE.md`, "Domain Model Value-Type Conformances").
public struct AnalysisSettings: Equatable, Hashable, Sendable {
    public let noiseFloorCalibrationMode: NoiseFloorCalibrationMode
    public let silenceThresholdDb: Double
    public let calibrationMarginDb: Double
    public let noiseFloorReestimationIntervalSeconds: Double
    public let analysisWindowMilliseconds: Double
    public let minimumSilenceDurationSeconds: Double
    public let minimumCueDurationSeconds: Double
    public let tailToleranceDb: Double
    public let tailCapSeconds: Double
    public let embeddedMarkerMergeToleranceSeconds: Double

    public init(
        noiseFloorCalibrationMode: NoiseFloorCalibrationMode = .manual,
        silenceThresholdDb: Double = -40.0,
        calibrationMarginDb: Double = 6.0,
        noiseFloorReestimationIntervalSeconds: Double = 300.0,
        analysisWindowMilliseconds: Double = 50.0,
        minimumSilenceDurationSeconds: Double = 2.0,
        minimumCueDurationSeconds: Double = 3.0,
        tailToleranceDb: Double = 6.0,
        tailCapSeconds: Double = 2.0,
        embeddedMarkerMergeToleranceSeconds: Double = 1.0
    ) {
        self.noiseFloorCalibrationMode = noiseFloorCalibrationMode
        self.silenceThresholdDb = silenceThresholdDb
        self.calibrationMarginDb = calibrationMarginDb
        self.noiseFloorReestimationIntervalSeconds = noiseFloorReestimationIntervalSeconds
        self.analysisWindowMilliseconds = analysisWindowMilliseconds
        self.minimumSilenceDurationSeconds = minimumSilenceDurationSeconds
        self.minimumCueDurationSeconds = minimumCueDurationSeconds
        self.tailToleranceDb = tailToleranceDb
        self.tailCapSeconds = tailCapSeconds
        self.embeddedMarkerMergeToleranceSeconds = embeddedMarkerMergeToleranceSeconds
    }
}

/// Whether `AnalysisSettings.silenceThresholdDb` is used directly, or
/// calibrated from the file's own measured noise floor (SPEC.md §4.11,
/// "Threshold: manual vs. automatic").
public enum NoiseFloorCalibrationMode: Equatable, Hashable, Sendable {
    case manual
    case automatic
}
