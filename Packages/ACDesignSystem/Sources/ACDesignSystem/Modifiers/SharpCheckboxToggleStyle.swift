import SwiftUI

/// A real, custom-drawn checkbox — no domain knowledge, just `Theme` tokens.
///
/// **Why this exists instead of `.toggleStyle(.checkbox)` plus `.tint(_:)`.**
/// `.checkbox`-style `Toggle` on macOS is backed by AppKit's native checkbox
/// rendering, and — confirmed by direct manual testing, not assumed —
/// `.tint(_:)` does not reach its checkmark/fill color the way it reliably
/// does for `Picker`/`.switch`-style `Toggle`: the box stays the system
/// accent color (blue) regardless. This is the exact same category of
/// problem `SharpButtonStyle` already exists to solve for buttons (a native
/// AppKit control whose visual chrome a SwiftUI modifier can't fully reach)
/// — the fix is the same shape: draw the control ourselves, don't rely on a
/// modifier reaching into AppKit's own rendering.
///
/// Applied everywhere a checkbox appears on the Setup screen —
/// `CheckboxGridView` (Production Type/Exploitation Type/Attachment Type)
/// and the standalone Sendedatum toggle — so every checkbox on the screen is
/// genuinely Burgundy, not just the ones a modifier happened to reach.
public struct SharpCheckboxToggleStyle: ToggleStyle {
    private let surface: Theme.Surface

    public init(surface: Theme.Surface = .primary) {
        self.surface = surface
    }

    public func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                box(isOn: configuration.isOn)
                configuration.label
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .pointingHandCursor()
    }

    /// **Root cause of an earlier "tapping the checkbox glyph only toggles
    /// ON→OFF, never OFF→ON" bug — confirmed by tracing the view hierarchy,
    /// not guessed.** The unchecked state's fill used to be `Color.clear`
    /// (genuinely zero alpha), leaving the box's interior with no real
    /// opaque content — only a `strokeBorder`'s thin 1pt ring. On macOS,
    /// `.contentShape(Rectangle())` on the outer `Button` does not reliably
    /// override a nested, fully-transparent (`Color.clear`) fill's own
    /// hit-testing exclusion for this `.plain`-button-with-custom-label
    /// configuration — the ring aside, the interior simply isn't tappable.
    /// When checked, the fill is `Theme.Colors.accent` (fully opaque), which
    /// *does* intercept taps directly via its own real pixels — exactly the
    /// asymmetry that was reported (OFF→ON only worked via the label text;
    /// ON→OFF worked via either, since the checked box has real opaque
    /// content to hit-test against).
    ///
    /// **Fix: never use a literally-zero-alpha fill.** The unchecked state
    /// now fills with `surface.background` — opaque, and visually
    /// indistinguishable from "no fill" since it matches the surrounding
    /// screen's own background exactly, but genuinely present for
    /// hit-testing purposes in both states identically. `.contentShape(
    /// Rectangle())` is also applied directly on the box itself, not only on
    /// the outer `Button`, as defense in depth.
    private func box(isOn: Bool) -> some View {
        ZStack {
            Rectangle()
                .fill(isOn ? Theme.Colors.accent : surface.background)
            Rectangle()
                .strokeBorder(isOn ? Theme.Colors.accent : surface.foreground.opacity(0.5), lineWidth: 1)
            if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.Colors.white)
            }
        }
        .frame(width: 15, height: 15)
        .contentShape(Rectangle())
        // Deliberately no `.clipShape`/`.cornerRadius` — sharp corners,
        // matching every other control in this design system.
    }
}

#Preview("SharpCheckboxToggleStyle") {
    struct PreviewHost: View {
        @State private var isOn = true
        @State private var isOff = false
        var body: some View {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Toggle("Checked", isOn: $isOn)
                    .toggleStyle(SharpCheckboxToggleStyle())
                Toggle("Unchecked", isOn: $isOff)
                    .toggleStyle(SharpCheckboxToggleStyle())
            }
            .padding(Theme.Spacing.lg)
            .background(Theme.Surface.primary.background)
        }
    }
    return PreviewHost()
}
