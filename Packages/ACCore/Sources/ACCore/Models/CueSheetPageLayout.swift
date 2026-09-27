import Foundation

/// One page's worth of fully-positioned content for the producer-facing cue
/// sheet PDF (SPEC.md §4.16, `ROADMAP.md` D11/T11.2) — landscape, its own
/// column-based design, distinct from the literal SUISA WA Film form (D12).
///
/// A plain, renderer-agnostic value type computed exactly once by
/// `ExportRepository` (`ACExport`, Data layer — real Core Text measurement
/// is required for pagination and isn't available in pure Foundation code)
/// and drawn identically by both `PDFCueSheetRenderer` (the real PDF) and
/// the on-screen preview View — see `CLAUDE.md`'s "Export Architecture"
/// section for the full guarantee this exists to provide.
public struct CueSheetPageLayout: Equatable, Hashable, Sendable {
    public let pageIndex: Int
    public let pageCount: Int
    public let elements: [CueSheetLayoutElement]

    public init(pageIndex: Int, pageCount: Int, elements: [CueSheetLayoutElement]) {
        self.pageIndex = pageIndex
        self.pageCount = pageCount
        self.elements = elements
    }
}
