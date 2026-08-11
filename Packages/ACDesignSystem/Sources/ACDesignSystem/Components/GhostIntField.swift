import SwiftUI

/// A single-line optional-integer text field with the same ghost/placeholder
/// styling as `GhostTextField` (`CLAUDE.md`'s Visual Language) — no domain
/// knowledge, just `Int?`/closures.
///
/// **Binds through a `String` internally, not `TextField(_:value:format:)`
/// directly.** SwiftUI's numeric `TextField` always renders a formatted
/// number for any non-`nil` value — including `0` — so coercing an unset
/// `Int?` to `0` at the binding boundary (as an earlier version of this
/// field's call sites did) makes the field display a literal "0" instead of
/// ever showing ghost placeholder text, and bakes in an unwanted default the
/// requester explicitly didn't want. Routing through a `String` (empty when
/// `nil`) is what makes an actually-empty field look empty.
///
/// Extracted at its third real call site (`Production Year`/`Season`/
/// `Episode`, `ROADMAP.md` D7's Setup screen reorder) per `CONTRIBUTING.md`
/// §3's rule of three — the same trigger `GhostTextField` itself was
/// extracted under.
public struct GhostIntField: View {
    private let placeholder: String
    @Binding private var value: Int?
    private let surface: Theme.Surface

    public init(placeholder: String, value: Binding<Int?>, surface: Theme.Surface = .primary) {
        self.placeholder = placeholder
        _value = value
        self.surface = surface
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { value.map(String.init) ?? "" },
            set: { newText in
                let trimmed = newText.trimmingCharacters(in: .whitespaces)
                value = trimmed.isEmpty ? nil : Int(trimmed)
            }
        )
    }

    public var body: some View {
        TextField("", text: textBinding, prompt: Text(placeholder).foregroundStyle(Theme.Colors.ghostTextPrimary))
            .textFieldStyle(.plain)
            .foregroundStyle(surface.foreground)
            .padding(Theme.Spacing.sm)
            .overlay(Rectangle().strokeBorder(surface.foreground.opacity(0.3), lineWidth: 1))
    }
}

#Preview("GhostIntField") {
    struct PreviewHost: View {
        @State private var value: Int?
        var body: some View {
            GhostIntField(placeholder: "Season", value: $value)
                .padding(Theme.Spacing.lg)
                .background(Theme.Surface.primary.background)
        }
    }
    return PreviewHost()
}
