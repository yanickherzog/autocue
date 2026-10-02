import ACCore
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
