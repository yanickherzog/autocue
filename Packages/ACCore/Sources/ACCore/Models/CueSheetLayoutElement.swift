import Foundation

/// One positioned piece of content on a `CueSheetPageLayout` page
/// (SPEC.md §4.16).
public struct CueSheetLayoutElement: Equatable, Hashable, Sendable {
    public let frame: LayoutRect
    public let content: LayoutElementContent

    public init(frame: LayoutRect, content: LayoutElementContent) {
        self.frame = frame
        self.content = content
    }
}

/// What a `CueSheetLayoutElement` actually draws — text, or a straight rule
/// line (a table border/divider). Deliberately minimal: this cue sheet's
/// design (SPEC.md §4.16, `ROADMAP.md` D11/T11.2) is a text table with rule
/// lines, nothing more elaborate (no logos/images anywhere in the real
/// example this Task is built from).
public enum LayoutElementContent: Equatable, Hashable, Sendable {
    case text(String, font: LayoutFontSpec)
    case rule(LayoutRuleSpec)
}

/// An abstract font description — weight + size (+ optional letter-spacing),
/// no font *name*. `ACCore` stays Foundation-only (`CLAUDE.md` rule 1), so it
/// can't name a concrete PostScript font; each rendering backend (Core
/// Graphics for the real PDF, SwiftUI for the on-screen preview) maps
/// `weight` to this app's one registered typeface (Space Grotesk,
/// `CLAUDE.md`'s Visual Language) at the point of drawing — the same
/// adapter-at-the-edge pattern `LayoutRect` establishes for geometry.
public struct LayoutFontSpec: Equatable, Hashable, Sendable {
    public let weight: LayoutFontWeight
    public let size: Double
    /// Extra space added between characters, in points (Core Text kerning) —
    /// `0` (the default) draws with the font's normal spacing. Added for the
    /// cue sheet PDF's eyebrow line (SPEC.md §4.16, `ROADMAP.md` D11/T11.2
    /// layout-redesign pass), which is deliberately letter-spaced small caps;
    /// every other existing call site keeps its two-argument form and is
    /// unaffected.
    public let tracking: Double

    public init(weight: LayoutFontWeight, size: Double, tracking: Double = 0) {
        self.weight = weight
        self.size = size
        self.tracking = tracking
    }
}

public enum LayoutFontWeight: Equatable, Hashable, Sendable {
    case regular
    case medium
    case bold
}

/// A straight rule line (table border/divider) — thickness only; drawing
/// backends supply color (this document renders on paper, not one of this
/// app's two on-screen surface styles, so there's no "primary vs. reversed"
/// choice to make here — see `CLAUDE.md`'s Visual Language). The line's
/// actual geometry is its owning `CueSheetLayoutElement.frame`, not repeated
/// here.
public struct LayoutRuleSpec: Equatable, Hashable, Sendable {
    public let thickness: Double

    public init(thickness: Double) {
        self.thickness = thickness
    }
}
