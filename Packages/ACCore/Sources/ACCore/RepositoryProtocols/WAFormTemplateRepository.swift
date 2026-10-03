import Foundation

/// The Data-layer boundary for the user's imported WA Film template PDFs
/// (`ROADMAP.md` D12, SPEC.md §2.1) — implemented by `ACExport`'s
/// `WAFormTemplateRepositoryImpl`, mirroring `AudioAnalysisRepository`'s own
/// security-scoped-bookmark lifecycle (SPEC.md §4.10), applied to a
/// user-imported reference PDF instead of a user-imported WAV file.
///
/// **Stored app-level, not routed through `Settings`.** `Settings` has no
/// `SettingsRepository` yet (`ROADMAP.md` D15/T15.1) — this repository is a
/// small, independent, `UserDefaults`-backed store (the same lightweight,
/// non-`SwiftData` precedent `ProjectWindowFrameStore` already establishes
/// in this codebase), reached through a proper Domain protocol only because
/// both `ACFeatures` (to know whether a template is configured) and
/// `ACExport` (to actually open the files at export time) need it, unlike
/// `ProjectWindowFrameStore`'s own App-target-local placement, which neither
/// layer below the App target can reach.
///
/// `Sendable` per `CLAUDE.md`, "Use Cases Are Stateless" — see
/// `ProjectRepository`'s doc comment for the same reasoning.
public protocol WAFormTemplateRepository: Sendable {
    /// Mints fresh security-scoped bookmarks for both files and persists the
    /// resulting reference, replacing any previously-stored one. Always
    /// attempts a real security-scoped bookmark first, falling back to a
    /// plain one if creation itself fails — the exact same fallback
    /// `AudioAnalysisRepository.importAudio(from:)` already established
    /// (SPEC.md §4.10, "Security-scoped bookmark creation can fail
    /// entirely"), applied to these two files independently (one file's
    /// bookmark creation failing doesn't affect the other's).
    func importTemplate(mainFormURL: URL, continuationFormURL: URL) throws -> WAFormTemplateReference

    /// The currently-stored reference, or `nil` if the user has never
    /// imported one — the signal the WA Film tab uses to decide between its
    /// import-prompt empty state and the real preview/export controls.
    func currentTemplate() -> WAFormTemplateReference?

    /// Checks whether either stored bookmark is stale and, if so, returns a
    /// fresh, fully-updated `WAFormTemplateReference` with just that
    /// bookmark replaced — `nil` when both are still current, nothing to do.
    /// Mirrors `AudioAnalysisRepository.refreshBookmarkIfStale(_:mode:)`
    /// exactly; callers that resolve a previously-stored template for real
    /// file access must call this first, the same "don't let a stale
    /// bookmark silently keep resolving" discipline SPEC.md §4.10 already
    /// establishes for `AudioAsset`.
    func refreshBookmarkIfStale(_ reference: WAFormTemplateReference) throws -> WAFormTemplateReference?
}
