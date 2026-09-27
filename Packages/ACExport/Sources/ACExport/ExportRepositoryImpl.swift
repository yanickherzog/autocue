import ACCore
import Foundation

/// The real `ExportRepository` implementation (`ROADMAP.md` D11/T11.2 for
/// `computeLayout` and the `.pdf` half of `export`; `.xlsx`/`.both` are
/// T11.4's job, once `XLSXCueSheetWriter` exists — see `ExportError` below).
public struct ExportRepositoryImpl: ExportRepository, Sendable {
    public enum ExportError: Error {
        /// `.xlsx`/`.both` aren't implemented yet — `XLSXCueSheetWriter`
        /// (`ROADMAP.md` D11/T11.4) doesn't exist. A real, honest error, not
        /// a silent no-op — thrown rather than pretending to succeed.
        case formatNotYetImplemented(ExportFormat)
    }

    public init() {}

    public func computeLayout(for project: Project) -> [CueSheetPageLayout] {
        CueSheetLayoutComputer.computeLayout(for: project)
    }

    public func export(
        project: Project,
        format: ExportFormat,
        to destination: URL
    ) -> AsyncThrowingStream<OperationProgress<URL>, Error> {
        AsyncThrowingStream { continuation in
            guard format == .pdf else {
                continuation.finish(throwing: ExportError.formatNotYetImplemented(format))
                return
            }
            do {
                let pages = CueSheetLayoutComputer.computeLayout(for: project)
                continuation.yield(.progress(ProgressUpdate(fractionCompleted: 0.5, message: "Rendering PDF…")))
                try PDFCueSheetRenderer.render(pages, to: destination)
                continuation.yield(.completed(destination))
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}
