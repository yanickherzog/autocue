import SwiftUI

/// A single-line text field with ghost/placeholder text per `CLAUDE.md`'s
/// Visual Language (Carbon Black at 40% opacity on the primary surface) and
/// a plain rectangular border — no domain knowledge, just `String`/closures.
///
/// Extracted at its third real call site (`ROADMAP.md` D7's `SetupView`
/// needs this same styled-field shape for roughly a dozen fields, on top of
/// the two already-duplicated instances in `ProjectLibraryView`'s
/// `NewProjectSheet`/search field) per `CONTRIBUTING.md` §3's rule of three.
/// The two existing D6 call sites are left as-is — not this Deliverable's
/// scope to retrofit, per `CONTRIBUTING.md` §3 ("keep it a separate commit
/// from the feature work").
public struct GhostTextField: View {
    private let placeholder: String
    @Binding private var text: String
    private let surface: Theme.Surface
    private let onSubmit: (() -> Void)?

    public init(
        placeholder: String,
        text: Binding<String>,
        surface: Theme.Surface = .primary,
        onSubmit: (() -> Void)? = nil
    ) {
        self.placeholder = placeholder
        _text = text
        self.surface = surface
        self.onSubmit = onSubmit
    }

    public var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Theme.Colors.ghostTextPrimary))
            .textFieldStyle(.plain)
            .foregroundStyle(surface.foreground)
            .padding(Theme.Spacing.sm)
            .overlay(Rectangle().strokeBorder(surface.foreground.opacity(0.3), lineWidth: 1))
            .onSubmit { onSubmit?() }
    }
}

#Preview("GhostTextField") {
    struct PreviewHost: View {
        @State private var text = ""
        var body: some View {
            GhostTextField(placeholder: "Project Name", text: $text)
                .padding(Theme.Spacing.lg)
                .background(Theme.Surface.primary.background)
        }
    }
    return PreviewHost()
}
