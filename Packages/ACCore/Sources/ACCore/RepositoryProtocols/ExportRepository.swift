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
    /// which are drawn from the user's own imported template pages as a
    /// background (`WAFormRenderer`). Reuses `CueSheetPageLayout`'s
    /// mechanism unchanged (SPEC.md §4.16's own open question, resolved: the
    /// type is already content-agnostic) — only the content and the
    /// fixed-position, fixed-capacity layout rule differ from the cue
    /// sheet's dynamic, pack-to-capacity one.
    ///
    /// **No `template:` parameter, unlike this method's original D12/T12.1
    /// signature** — there is only ever one app-level template
    /// (`WAFormTemplateReference`'s own doc comment), so this method reads
    /// whichever one is currently imported via the same
    /// `WAFormTemplateRepository` the Impl already holds, rather than the
    /// caller threading a reference value through that no longer carries
    /// any file-location data to act on (`ROADMAP.md` D12/T12.4,
    /// `docs/DECISIONS.md`). Throws `WAFormError.noTemplateConfigured` (the
    /// concrete type `ExportRepositoryImpl` defines) if none is imported —
    /// callers that already know `WAFormTemplateUseCase.currentTemplate()`
    /// is non-`nil` won't normally hit this.
    func computeWAFormLayout(for project: Project) throws -> [CueSheetPageLayout]

    /// The real, live page count of the currently-imported continuation-form
    /// file (`ROADMAP.md` D12/T12.3) — the same value
    /// `computeWAFormLayout(for:)` already resolves internally to pass as
    /// `WAFormLayoutComputer.computeLayout`'s `continuationPagesAvailable`,
    /// exposed as its own method so `ValidateWAFormUseCase` can determine
    /// real export-capacity (SPEC.md §2.1's 5-main-form/4-per-continuation-
    /// page rule) without computing a full layout just to read this one
    /// number.
    ///
    /// Returns `nil` — not an error — when no template is imported at all;
    /// throws only if a template *is* imported but its own file genuinely
    /// can't be read (rare now that it's AutoCue's own private copy, not an
    /// external file subject to being moved/renamed).
    func continuationTemplatePageCount() throws -> Int?

    /// Renders the WA Film registration form (`ROADMAP.md` D12) by drawing
    /// `computeWAFormLayout(for:)`'s overlay elements on top of the
    /// currently-imported template's own real pages
    /// (`CGPDFDocument`/`drawPDFPage`, plain Core Graphics — never
    /// `PDFKit`), writing a brand-new output PDF to `destination`. The
    /// user's own imported copy is never modified. Throws
    /// `WAFormError.noTemplateConfigured` if none is imported.
    func exportWAForm(project: Project, to destination: URL) -> AsyncThrowingStream<OperationProgress<URL>, Error>
}
