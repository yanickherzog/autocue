import SwiftUI

public extension View {
    /// Forces this view's native AppKit-backed controls (`TextField`'s
    /// `prompt:`, `Picker`'s selected-value display, `DatePicker`, `List`'s
    /// own background material) to render using `surface`'s intended
    /// light/dark appearance, regardless of the system's actual Light/Dark
    /// Mode setting.
    ///
    /// **Why this is needed at all:** `CLAUDE.md`'s Visual Language commits
    /// this app to a fixed, non-adaptive appearance — but that commitment
    /// was never actually enforced for native controls before `ROADMAP.md`
    /// D7's Setup screen exercised enough of them to expose it. A plain
    /// SwiftUI `Text` with an explicit `.foregroundStyle()` already renders
    /// correctly regardless of system appearance (D6 already fixed a
    /// TextField's *typed*-text color this same way). But several native
    /// control surfaces render via AppKit-internal paths that don't respect
    /// `.foregroundStyle()` at all: a `TextField`'s `prompt:` placeholder, a
    /// `Picker`'s own selected-value label, and (separately) a `List`'s
    /// native background material — all three follow the system's actual
    /// Dark/Light Mode setting no matter what SwiftUI-level styling is
    /// applied, confirmed by direct rendering tests (a real windowed test
    /// app screenshotted under this session's actual system Dark Mode
    /// state) rather than assumed. `.environment(\.colorScheme:)` is the one
    /// override that reaches those AppKit-internal paths.
    ///
    /// Apply once, at a screen's root — `SetupView` and its sheets
    /// (`PartyPickerView`/`PersonEditorSheet`/`LabelEditorSheet`) are D7's
    /// first real users. `List`'s background material specifically still
    /// also needs its own explicit `.scrollContentBackground(.hidden)` +
    /// `.background()` fix (`ProjectLibraryView` already established this
    /// pattern at D6) — this modifier doesn't replace that, the two address
    /// different rendering paths that happened to share the same underlying
    /// cause (native chrome following real system appearance).
    func fixedAppearance(for surface: Theme.Surface) -> some View {
        environment(\.colorScheme, surface == .primary ? .light : .dark)
    }
}
