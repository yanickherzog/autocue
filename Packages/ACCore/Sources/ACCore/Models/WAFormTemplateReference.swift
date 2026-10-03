import Foundation

/// A reference to the user's own, legitimately-downloaded copy of the real
/// SUISA WA Film registration form PDFs (`ROADMAP.md` D12) — the main form
/// (`WA Film 2007-01`) and its continuation form (`WA Film II 2007-01`,
/// SPEC.md §2.1).
///
/// **App-level, not per-`Project` — a deliberate difference from
/// `AudioAsset`.** The user's WA Film template is the same file reused for
/// every declaration across every `Project`; there is no reason to import it
/// per-`Project` the way `AudioAsset` is (a different physical recording
/// each time). This also avoids a real dependency this Deliverable would
/// otherwise have on `Settings`/`SettingsRepository`, which doesn't exist
/// until `ROADMAP.md` D15/T15.1 — see `WAFormTemplateRepository`'s own doc
/// comment for where this is actually stored.
///
/// **AutoCue never bundles SUISA's own form inside the app.** The export
/// feature draws `Setup`/`Cue` data as an overlay directly on top of
/// whichever specific file the user imported here — plain Core Graphics
/// (`CGPDFDocument`/`drawPDFPage`), never `PDFKit`, never a shipped resource.
/// This sidesteps any redistribution question entirely, at the cost of
/// requiring a one-time import step before the WA Film tab can produce real
/// output. See `docs/DECISIONS.md`.
///
/// Two independent bookmarks (one per file), not one bookmark to a folder —
/// mirrors `AudioAsset.securityScopedBookmark`'s per-file shape exactly.
/// Conformances: `Equatable`, `Sendable` (`CLAUDE.md`, "Domain Model
/// Value-Type Conformances" — no `id` field; there is only ever one
/// app-level template reference, nothing to disambiguate by identity). No
/// `Codable` — no real feature needs it.
public struct WAFormTemplateReference: Equatable, Sendable {
    public let mainFormBookmark: Data
    public let mainFormAccessMode: BookmarkAccessMode
    public let mainFormFileName: String
    public let continuationFormBookmark: Data
    public let continuationFormAccessMode: BookmarkAccessMode
    public let continuationFormFileName: String
    public let importedAt: Date

    public init(
        mainFormBookmark: Data,
        mainFormAccessMode: BookmarkAccessMode,
        mainFormFileName: String,
        continuationFormBookmark: Data,
        continuationFormAccessMode: BookmarkAccessMode,
        continuationFormFileName: String,
        importedAt: Date
    ) {
        self.mainFormBookmark = mainFormBookmark
        self.mainFormAccessMode = mainFormAccessMode
        self.mainFormFileName = mainFormFileName
        self.continuationFormBookmark = continuationFormBookmark
        self.continuationFormAccessMode = continuationFormAccessMode
        self.continuationFormFileName = continuationFormFileName
        self.importedAt = importedAt
    }
}
