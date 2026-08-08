import Foundation

/// App-level settings — not part of the SUISA document, not project-scoped
/// (SPEC.md §4.7). No `id` field: `Settings` is a single app-wide value, not
/// an entity with independent identity (`CLAUDE.md`, "Domain Model
/// Value-Type Conformances"). No `SettingsRepository` exists yet — that's
/// `ROADMAP.md` D14/T14.1's job; nothing in this Deliverable fetches or
/// persists a `Settings` value, only composes the type itself.
public struct Settings: Equatable, Sendable {
    public let defaultDeclarant: Party?
    public let defaultProductionCountry: String?
    public let exportLanguage: ExportLanguage
    public let autoComputeTotalMusicRuntime: Bool
    public let shareValidationStrictness: ShareValidationStrictness
    public let defaultExportFormat: ExportFormat
    public let audioAnalysisDefaults: AnalysisSettings

    public init(
        defaultDeclarant: Party? = nil,
        defaultProductionCountry: String? = nil,
        exportLanguage: ExportLanguage = .en,
        autoComputeTotalMusicRuntime: Bool = true,
        shareValidationStrictness: ShareValidationStrictness = .warnOnly,
        defaultExportFormat: ExportFormat = .both,
        audioAnalysisDefaults: AnalysisSettings = AnalysisSettings()
    ) {
        self.defaultDeclarant = defaultDeclarant
        self.defaultProductionCountry = defaultProductionCountry
        self.exportLanguage = exportLanguage
        self.autoComputeTotalMusicRuntime = autoComputeTotalMusicRuntime
        self.shareValidationStrictness = shareValidationStrictness
        self.defaultExportFormat = defaultExportFormat
        self.audioAnalysisDefaults = audioAnalysisDefaults
    }
}

/// SUISA's *WA Film* form exists in all four Swiss/working languages
/// (SPEC.md §4.7).
public enum ExportLanguage: Equatable, Sendable {
    case de
    case fr
    case it
    case en
}

/// Whether a failed SPEC.md §4.6 validation rule blocks export or only warns
/// (SPEC.md §4.7).
public enum ShareValidationStrictness: Equatable, Sendable {
    case warnOnly
    case blockExport
}

/// Which file format(s) a given export run produces — also the parameter
/// type `ExportCueSheetUseCase`/`ExportRepository` take to select that
/// (`ROADMAP.md` D11), not a concept independent from `Settings.
/// defaultExportFormat` (SPEC.md §4.7).
public enum ExportFormat: Equatable, Sendable {
    case pdf
    case xlsx
    case both
}
