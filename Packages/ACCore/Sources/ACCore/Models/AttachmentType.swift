import Foundation

/// The SUISA form's "Attachment(s)" checkbox group (SPEC.md §4.2.2) —
/// informational flags only; the app does not manage the physical
/// attachments themselves.
///
/// Modeled as a `Set<AttachmentType>` on `Setup`, since a declaration can
/// legitimately carry more than one kind of attachment at once.
public enum AttachmentType: Equatable, Hashable, CaseIterable, Sendable {
    case score
    case agreement
    case soundOrVideoCarrier
    case other
}
