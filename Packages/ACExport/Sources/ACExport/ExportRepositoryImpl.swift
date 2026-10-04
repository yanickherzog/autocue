import ACCore
import CoreGraphics
import Foundation

/// The real `ExportRepository` implementation (`ROADMAP.md` D11) — PDF since
/// T11.2, XLSX since T11.4/T11.5's wiring below.
///
/// **`.both` is handled by the caller, not this type** (`ROADMAP.md`
/// D11/T11.5, project-owner decision): `OperationProgress<URL>.completed`
/// fires exactly once, which doesn't fit two output files cleanly, and
/// `ExportFormat.both` would need a real `ACCore` protocol signature change
/// (`[URL]` instead of `URL`) to represent two completions. Rejected as
/// disproportionate for two output files — `ExportViewModel` (`ACFeatures`)
/// instead calls `export(project:format:to:)` twice for `.both`, once per
/// concrete format, deriving each destination's path itself. `.both` is
/// therefore never a valid `format` argument here — see `ExportError` below.
///
/// **Security-scoped access is bracketed here, at the point of actual file
/// I/O** — never in a View/ViewModel — the same pattern
/// `AudioAnalysisRepositoryImpl` already establishes for the import side
/// (`start`/`stopAccessingSecurityScopedResource()` around the real read).
/// Unlike that side's bookmark-persistence complexity (`SPEC.md` §4.10, D8),
/// export needs none of it: the access `.fileExporter`'s Powerbox grant
/// provides only needs to last for this one write, never persisted or
/// resolved again later.
public struct ExportRepositoryImpl: ExportRepository, Sendable {
    public enum ExportError: Error, Equatable {
        /// `.both` isn't a valid argument to this method — see this type's
        /// own doc comment for why splitting it into two calls is the
        /// caller's job, not this Data-layer type's.
        case bothIsNotASingleExportOperation
        /// The `.fileExporter`/`NSSavePanel`-granted `destination` couldn't
        /// actually be accessed — `startAccessingSecurityScopedResource()`
        /// returned `false`. A real, honest error, not a silent attempt to
        /// write anyway.
        case destinationAccessDenied
    }

    public init() {}

    public func computeLayout(for project: Project) -> [CueSheetPageLayout] {
        CueSheetLayoutComputer.computeLayout(for: project)
    }

    public enum WAFormError: Error, Equatable {
        case templateAccessDenied
        case couldNotOpenTemplate
    }

    public func computeWAFormLayout(
        for project: Project,
        template: WAFormTemplateReference
    ) throws -> [CueSheetPageLayout] {
        let continuationPageCount = try continuationTemplatePageCount(for: template)
        return WAFormLayoutComputer.computeLayout(for: project, continuationPagesAvailable: continuationPageCount)
    }

    public func continuationTemplatePageCount(for template: WAFormTemplateReference) throws -> Int {
        try Self.withResolvedTemplateDocument(
            bookmark: template.continuationFormBookmark,
            mode: template.continuationFormAccessMode
        ) { $0.numberOfPages }
    }

    public func exportWAForm(
        project: Project,
        template: WAFormTemplateReference,
        to destination: URL
    ) -> AsyncThrowingStream<OperationProgress<URL>, Error> {
        AsyncThrowingStream { continuation in
            guard destination.startAccessingSecurityScopedResource() else {
                continuation.finish(throwing: WAFormError.templateAccessDenied)
                return
            }
            defer { destination.stopAccessingSecurityScopedResource() }
            do {
                continuation.yield(.progress(ProgressUpdate(fractionCompleted: 0.3, message: "Reading template…")))
                try Self.withResolvedTemplateDocuments(template: template) { mainDocument, continuationDocument in
                    continuation.yield(.progress(ProgressUpdate(fractionCompleted: 0.6, message: "Rendering…")))
                    let pages = WAFormLayoutComputer.computeLayout(
                        for: project,
                        continuationPagesAvailable: continuationDocument.numberOfPages
                    )
                    try WAFormRenderer.render(
                        pages,
                        mainFormDocument: mainDocument,
                        continuationFormDocument: continuationDocument,
                        mainPageCount: 2,
                        to: destination
                    )
                }
                continuation.yield(.completed(destination))
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    /// Resolves a single bookmark to a real, security-scope-bracketed
    /// `CGPDFDocument` for the duration of `body`, then releases access —
    /// used by `computeWAFormLayout(for:template:)`, which only needs to
    /// read the continuation file's page count, not render anything.
    private static func withResolvedTemplateDocument<T>(
        bookmark: Data,
        mode: BookmarkAccessMode,
        _ body: (CGPDFDocument) throws -> T
    ) throws -> T {
        let url = try WAFormTemplateRepositoryImpl.resolveURL(bookmark: bookmark, mode: mode)
        guard url.startAccessingSecurityScopedResource() else {
            throw WAFormError.templateAccessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let document = CGPDFDocument(url as CFURL) else {
            throw WAFormError.couldNotOpenTemplate
        }
        return try body(document)
    }

    /// Resolves both of `template`'s bookmarks to real, security-scope-
    /// bracketed `CGPDFDocument`s for the duration of `body`, then releases
    /// both — used by `exportWAForm`, which needs both real files open at
    /// once to render. Extracted from `exportWAForm` itself specifically to
    /// keep that method's own body under `CONTRIBUTING.md` §8's `SwiftLint`
    /// length limit, the same reason `CueSheetLayoutComputer` splits across
    /// several `+`-suffixed files.
    private static func withResolvedTemplateDocuments<T>(
        template: WAFormTemplateReference,
        _ body: (CGPDFDocument, CGPDFDocument) throws -> T
    ) throws -> T {
        try withResolvedTemplateDocument(
            bookmark: template.mainFormBookmark,
            mode: template.mainFormAccessMode
        ) { mainDocument in
            try withResolvedTemplateDocument(
                bookmark: template.continuationFormBookmark,
                mode: template.continuationFormAccessMode
            ) { continuationDocument in
                try body(mainDocument, continuationDocument)
            }
        }
    }

    public func export(
        project: Project,
        format: ExportFormat,
        to destination: URL
    ) -> AsyncThrowingStream<OperationProgress<URL>, Error> {
        AsyncThrowingStream { continuation in
            guard format != .both else {
                continuation.finish(throwing: ExportError.bothIsNotASingleExportOperation)
                return
            }
            guard destination.startAccessingSecurityScopedResource() else {
                continuation.finish(throwing: ExportError.destinationAccessDenied)
                return
            }
            defer { destination.stopAccessingSecurityScopedResource() }
            do {
                switch format {
                case .pdf:
                    let pages = CueSheetLayoutComputer.computeLayout(for: project)
                    continuation.yield(.progress(ProgressUpdate(fractionCompleted: 0.5, message: "Rendering PDF…")))
                    try PDFCueSheetRenderer.render(pages, to: destination)
                case .xlsx:
                    continuation.yield(.progress(ProgressUpdate(fractionCompleted: 0.5, message: "Writing XLSX…")))
                    try XLSXCueSheetWriter.write(project, to: destination)
                case .both:
                    preconditionFailure("Excluded by the guard above")
                }
                continuation.yield(.completed(destination))
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}
