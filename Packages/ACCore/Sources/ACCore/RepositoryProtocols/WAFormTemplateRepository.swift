import Foundation

/// The Data-layer boundary for the user's imported WA Film template PDFs
/// (`ROADMAP.md` D12, SPEC.md §2.1) — implemented by `ACExport`'s
/// `WAFormTemplateRepositoryImpl`, which copies the user's two
/// `.fileImporter`-granted files into AutoCue's own private sandbox
/// container at import time and reads from that copy from then on.
///
/// **No bookmark lifecycle here, unlike `AudioAnalysisRepository`'s own
/// `AudioAsset` bookmark — a deliberate difference, not an oversight.**
/// `AudioAsset` must track an *external* file (a different recording per
/// import, never copied, since a multi-GB WAV shouldn't be duplicated).
/// This template is small, genuinely fixed, and reused forever once
/// imported, so `WAFormTemplateRepositoryImpl` copies it once and owns that
/// copy outright — no stale-bookmark class of failure to defend against at
/// all. See `docs/DECISIONS.md` for the real investigation (a genuine
/// relaunch-survival test on the earlier bookmark-based design actually
/// passed) that led to this simplification anyway, for robustness
/// independent of that one test's result.
///
/// **Stored app-level, not routed through `Settings`.** `Settings` has no
/// `SettingsRepository` yet (`ROADMAP.md` D15/T15.1) — this repository is a
/// small, independent, `UserDefaults`-backed store (the same lightweight,
/// non-`SwiftData` precedent `ProjectWindowFrameStore` already establishes
/// in this codebase), reached through a proper Domain protocol only because
/// both `ACFeatures` (to know whether a template is configured, and to open
/// the real files for its own on-screen preview) and `ACExport` (to render/
/// export) need it, unlike `ProjectWindowFrameStore`'s own App-target-local
/// placement, which neither layer below the App target can reach.
///
/// `Sendable` per `CLAUDE.md`, "Use Cases Are Stateless" — see
/// `ProjectRepository`'s doc comment for the same reasoning.
public protocol WAFormTemplateRepository: Sendable {
    /// Copies both of the user's selected files into AutoCue's own private
    /// container, replacing any previously-imported copy, and persists the
    /// resulting metadata. The user's original files are never modified;
    /// AutoCue's own copies are written fresh each time this is called.
    func importTemplate(mainFormURL: URL, continuationFormURL: URL) throws -> WAFormTemplateReference

    /// The currently-stored reference, or `nil` if the user has never
    /// imported one, **or if either previously-imported copy is no longer
    /// present on disk** (e.g. the app's container was manually tampered
    /// with) — this is the one signal the WA Film tab uses to decide between
    /// its import-prompt empty state and the real preview/export controls,
    /// so it must never report a template as present when its real files
    /// aren't actually there to open.
    func currentTemplate() -> WAFormTemplateReference?

    /// The real, ready-to-open file URLs for the currently-imported
    /// template's own private copy — `nil` under the exact same condition
    /// `currentTemplate()` returns `nil`. Callers never need to bracket
    /// these with `startAccessingSecurityScopedResource()`: they point
    /// inside AutoCue's own sandbox container, which the app always has
    /// standing read access to, not a user-selected external location.
    func templateFileURLs() -> (mainFormURL: URL, continuationFormURL: URL)?
}
