import ACCore
import Foundation

/// An in-memory `ExportRepository` fake (`ROADMAP.md` D3/T3.4) — returns a
/// canned destination `URL` rather than writing any real file, per
/// `CONTRIBUTING.md` §5. Real `ACExport` behavior is tested against real
/// generated PDF/XLSX output files (`ROADMAP.md` D11).
public struct InMemoryExportRepository: ExportRepository, Sendable {
    public let exportedURL: URL
    public let layoutToReturn: [CueSheetPageLayout]
    public let waFormLayoutToReturn: [CueSheetPageLayout]
    public let waFormLayoutError: Error?
    public let continuationTemplatePageCountToReturn: Int
    public let continuationTemplatePageCountError: Error?

    public init(
        exportedURL: URL = URL(fileURLWithPath: "/tmp/fixture-export"),
        layoutToReturn: [CueSheetPageLayout] = [],
        waFormLayoutToReturn: [CueSheetPageLayout] = [],
        waFormLayoutError: Error? = nil,
        continuationTemplatePageCountToReturn: Int = 5,
        continuationTemplatePageCountError: Error? = nil
    ) {
        self.exportedURL = exportedURL
        self.layoutToReturn = layoutToReturn
        self.waFormLayoutToReturn = waFormLayoutToReturn
        self.waFormLayoutError = waFormLayoutError
        self.continuationTemplatePageCountToReturn = continuationTemplatePageCountToReturn
        self.continuationTemplatePageCountError = continuationTemplatePageCountError
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

    public func computeLayout(for _: Project) -> [CueSheetPageLayout] {
        layoutToReturn
    }

    public func computeWAFormLayout(
        for _: Project,
        template _: WAFormTemplateReference
    ) throws -> [CueSheetPageLayout] {
        if let waFormLayoutError {
            throw waFormLayoutError
        }
        return waFormLayoutToReturn
    }

    public func continuationTemplatePageCount(for _: WAFormTemplateReference) throws -> Int {
        if let continuationTemplatePageCountError {
            throw continuationTemplatePageCountError
        }
        return continuationTemplatePageCountToReturn
    }

    public func exportWAForm(
        project _: Project,
        template _: WAFormTemplateReference,
        to destination: URL
    ) -> AsyncThrowingStream<OperationProgress<URL>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.progress(ProgressUpdate(fractionCompleted: 1.0)))
            continuation.yield(.completed(destination))
            continuation.finish()
        }
    }
}
