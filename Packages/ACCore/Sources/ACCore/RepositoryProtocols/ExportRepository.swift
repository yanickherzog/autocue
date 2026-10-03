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
    /// SUISA WA Film form's own layout (D12, below).
    func computeLayout(for project: Project) -> [CueSheetPageLayout]

    /// Computes the literal WA Film registration form's page-by-page
    /// **overlay** content (`ROADMAP.md` D12) — the dynamic field values
    /// only (text + checkbox marks), never the form's own labels/boxes,
    /// which are drawn from `template`'s own pages as a background
    /// (`WAFormRenderer`). Reuses `CueSheetPageLayout`'s mechanism unchanged
    /// (SPEC.md §4.16's own open question, resolved: the type is already
    /// content-agnostic) — only the content and the fixed-position,
    /// fixed-capacity layout rule differ from the cue sheet's dynamic,
    /// pack-to-capacity one.
    ///
    /// **Throwing, unlike `computeLayout(for:)` above** — a real, deliberate
    /// difference: this method must resolve `template`'s security-scoped
    /// bookmarks and read the continuation file's real page count to know
    /// how many continuation pages are actually available, which is genuine
    /// file I/O that can fail (the file moved, access revoked) in a way the
    /// cue sheet's pure in-memory layout math never can.
    func computeWAFormLayout(for project: Project, template: WAFormTemplateReference) throws -> [CueSheetPageLayout]

    /// Renders the WA Film registration form (`ROADMAP.md` D12) by drawing
    /// `computeWAFormLayout(for:template:)`'s overlay elements on top of
    /// `template`'s own real pages (`CGPDFDocument`/`drawPDFPage`, plain
    /// Core Graphics — never `PDFKit`), writing a brand-new output PDF to
    /// `destination`. `template`'s own stored files are never modified.
    func exportWAForm(project: Project, template: WAFormTemplateReference, to destination: URL)
        -> AsyncThrowingStream<OperationProgress<URL>, Error>
}
