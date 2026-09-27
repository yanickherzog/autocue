import Foundation

/// The Data-layer boundary for cue sheet export — implemented by
/// `ACExport`'s `ExportRepositoryImpl` (`ROADMAP.md` D11/T11.2 for
/// `computeLayout`; `export` filled in fully for `.pdf` at the same Task,
/// with `.xlsx`/`.both` deferred to T11.4's `XLSXCueSheetWriter`, which
/// doesn't exist yet — see that type's own doc comment).
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

    /// Computes the producer-facing cue sheet PDF's page-by-page layout
    /// (SPEC.md §4.16, `ROADMAP.md` D11/T11.2) — one `CueSheetPageLayout`
    /// per page, real Core Text measurement required for pagination, which
    /// is why this is a Data-layer method rather than a pure `ACCore`
    /// function. Both `PDFCueSheetRenderer` (the real PDF) and the
    /// on-screen preview View draw this identical, precomputed result —
    /// neither re-derives layout independently. Distinct from the literal
    /// SUISA WA Film form's own layout (D12, not this method's concern).
    func computeLayout(for project: Project) -> [CueSheetPageLayout]
}
