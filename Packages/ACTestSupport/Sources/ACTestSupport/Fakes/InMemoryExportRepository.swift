import ACCore
import Foundation

/// An in-memory `ExportRepository` fake (`ROADMAP.md` D3/T3.4) — returns a
/// canned destination `URL` rather than writing any real file, per
/// `CONTRIBUTING.md` §5. Real `ACExport` behavior is tested against real
/// generated PDF/XLSX output files (`ROADMAP.md` D11).
public struct InMemoryExportRepository: ExportRepository, Sendable {
    public let exportedURL: URL

    public init(exportedURL: URL = URL(fileURLWithPath: "/tmp/fixture-export")) {
        self.exportedURL = exportedURL
    }

    public func export(
        project _: Project,
        format _: ExportFormat,
        to _: URL
    ) -> AsyncThrowingStream<OperationProgress<URL>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.progress(ProgressUpdate(fractionCompleted: 1.0)))
            continuation.yield(.completed(exportedURL))
            continuation.finish()
        }
    }
}
