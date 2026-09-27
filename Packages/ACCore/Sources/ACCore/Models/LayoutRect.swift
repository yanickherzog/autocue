import Foundation

/// A plain, Foundation-only geometry primitive for `CueSheetLayoutElement`'s
/// `frame` (SPEC.md §4.16) — deliberately **not** `CGRect`, to keep `ACCore`
/// unambiguously Foundation-only per `CLAUDE.md` rule 1 (`CGRect` is a Core
/// Graphics type). Each rendering backend (Core Graphics for the real PDF,
/// SwiftUI for the on-screen preview) converts this to its own native
/// geometry type at the point of drawing — the same adapter-at-the-edge
/// pattern `WaveformDisplayData` (SPEC.md §4.15) already establishes.
///
/// Units are points (1/72 inch), matching Core Graphics' own native PDF
/// coordinate space directly — no unit conversion needed at the point of
/// drawing.
public struct LayoutRect: Equatable, Hashable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}
