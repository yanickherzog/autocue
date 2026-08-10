import AppKit
import SwiftUI

public extension View {
    /// Shows the pointing-hand cursor while hovering over this view —
    /// matching the "hovering over something interactive should look
    /// interactive" behavior a `TextField` already gets for free from AppKit
    /// (its I-beam cursor), applied to custom controls that don't (manual
    /// verification follow-up). Centralized here, once, so every genuinely
    /// clickable control — `SharpButtonStyle`-styled buttons, or a
    /// non-`Button` tappable control like a search field's icon — shares one
    /// implementation rather than each re-pairing `NSCursor.push`/`.pop`
    /// independently, which is easy to get unbalanced.
    func pointingHandCursor() -> some View {
        onHover { isHovering in
            if isHovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
