import Foundation
import PDFKit

/// Which of the two real SUISA WA Film documents an imported PDF is
/// (`ROADMAP.md` D12/T12.4) — used to auto-detect which of the two files the
/// user selected is the main form and which is the continuation form, so
/// the import flow needs only one combined file picker, not two separate
/// "which is which" pickers.
enum WAFormTemplateKind: Equatable {
    case mainForm
    case continuationForm
}

/// **Uses `PDFKit`'s `PDFDocument.string` for real text extraction — a
/// deliberate, explicitly-approved extension of `CLAUDE.md`'s documented
/// PDFKit role** (previously scoped to "lightweight in-app preview of an
/// already-generated PDF only," `docs/DECISIONS.md`, D12/T12.4). This is a
/// third, narrower use: read-only text extraction from a user-*imported*
/// file purely to classify it, no rendering, no preview, no generation
/// involved — confirmed acceptable directly rather than silently stretched.
/// The alternative (hand-rolled `CGPDFScanner`-based text extraction) would
/// mean reinventing a large, fragile piece of PDFKit's own functionality
/// for comparatively low value.
enum WAFormTemplateClassifier {
    /// Opens `url` and classifies it — `nil` if the file can't be opened at
    /// all, or if neither the extracted text nor the page-count fallback
    /// below can confidently identify it as either real document.
    static func classify(fileAt url: URL) -> WAFormTemplateKind? {
        guard let document = PDFDocument(url: url) else { return nil }
        return classify(text: document.string, pageCount: document.pageCount)
    }

    /// The pure half, directly unit-testable with no real PDF I/O needed —
    /// `WAFormTemplateClassifierTests` exercises this directly.
    ///
    /// **Text match first, page count only as a fallback for inconclusive
    /// text** (a scanned/non-text PDF, or extraction simply failing) — text
    /// is the authoritative signal per the real documents' own content;
    /// page count is a real, confirmed fact about the main form specifically
    /// (always exactly 2 pages, SPEC.md §2.1/§4.24) but says nothing
    /// reliable about the continuation form's own page count, which varies
    /// by how many pages the user's specific copy happens to have.
    ///
    /// **Continuation is checked before plain "WA Film"** — the
    /// continuation form's own title literally contains "WA Film II",
    /// which also contains the substring "WA Film"; checking the more
    /// specific match first avoids every continuation form being
    /// misclassified as a main form.
    static func classify(text: String?, pageCount: Int) -> WAFormTemplateKind? {
        let normalized = (text ?? "")
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()

        let mentionsContinuation = normalized.contains("wa film ii")
            || normalized.contains("zusatzliche werke")
            || normalized.contains("additional works")
        if mentionsContinuation {
            return .continuationForm
        }

        if normalized.contains("wa film") {
            return .mainForm
        }

        if pageCount == 2 {
            return .mainForm
        }

        return nil
    }
}
