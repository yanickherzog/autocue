import Foundation

/// The Data-layer boundary for cue sheet export — implemented by
/// `ACExport`'s `ExportRepositoryImpl` (`ROADMAP.md` D11/T11.5).
///
/// **Deliberately thin as of this Deliverable.** `CueSheetPageLayout`
/// (SPEC.md §4.16) — the shared, precomputed layout both the on-screen
/// preview and the real PDF renderer draw — doesn't exist until
/// `ROADMAP.md` D11/T11.2, so a `computeLayout(for:) -> CueSheetPageLayout`
/// method can't be declared yet. It's added to this protocol then, once that
/// type exists; this is not an oversight to "fix" before that point.
///
/// `Sendable` per `CLAUDE.md`, "Use Cases Are Stateless" — see
/// `ProjectRepository`'s doc comment for the same reasoning.
public protocol ExportRepository: Sendable {
    /// Exports `project` as `format`, writing to `destination` (typically an
    /// `NSSavePanel`-granted `URL`). Progress via the shared
    /// `AsyncThrowingStream<OperationProgress<T>, Error>` contract
    /// (`CLAUDE.md`, "Long-Running Operations") — one method for both PDF and
    /// XLSX, selected by `format`, not a separate contract per format
    /// (`CLAUDE.md` rule 2).
    func export(project: Project, format: ExportFormat, to destination: URL)
        -> AsyncThrowingStream<OperationProgress<URL>, Error>
}
