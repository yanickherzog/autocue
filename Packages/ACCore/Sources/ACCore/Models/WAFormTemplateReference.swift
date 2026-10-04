import Foundation

/// Metadata about the user's own, legitimately-downloaded copy of the real
/// SUISA WA Film registration form PDFs (`ROADMAP.md` D12) — the main form
/// (`WA Film 2007-01`) and its continuation form (`WA Film II 2007-01`,
/// SPEC.md §2.1) — imported once and reused for every `Project`.
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
/// **AutoCue never bundles SUISA's own form inside the app** — the shipped
/// `.app` bundle itself never contains a copy. `WAFormTemplateRepositoryImpl`
/// copies the user's own selected files into AutoCue's private, per-user
/// sandbox container at import time (`ROADMAP.md` D12/T12.4) rather than
/// tracking the original external files by security-scoped bookmark — see
/// `docs/DECISIONS.md` for the real finding that prompted dropping bookmarks
/// here specifically (a genuine relaunch-survival test passed on the
/// bookmark-based design, but the user's explicit requirement was a fully
/// automatic, never-again-asked experience with zero dependency on the
/// original external file continuing to exist at its original location —
/// a private copy removes that dependency class entirely, for a file that,
/// unlike `AudioAsset`'s own recording, never legitimately changes). This
/// type itself carries no bookmark or file-location data at all — that's
/// `WAFormTemplateRepository`'s own internal, Data-layer detail
/// (`WAFormTemplateRepository.templateFileURLs()`).
///
/// This type is now pure display/identity metadata — no `id` field (there is
/// only ever one app-level template reference, nothing to disambiguate by
/// identity; `CLAUDE.md`, "Domain Model Value-Type Conformances").
/// Conformances: `Equatable`, `Sendable`. No `Codable` — no real feature
/// needs it.
public struct WAFormTemplateReference: Equatable, Sendable {
    public let mainFormFileName: String
    public let continuationFormFileName: String
    public let importedAt: Date

    public init(mainFormFileName: String, continuationFormFileName: String, importedAt: Date) {
        self.mainFormFileName = mainFormFileName
        self.continuationFormFileName = continuationFormFileName
        self.importedAt = importedAt
    }
}
