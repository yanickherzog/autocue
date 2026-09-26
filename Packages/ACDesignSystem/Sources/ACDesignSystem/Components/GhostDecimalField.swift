import SwiftUI

/// A single-line optional-`Decimal` text field with the same ghost/placeholder
/// styling as `GhostTextField`/`GhostIntField` (`CLAUDE.md`'s Visual
/// Language) — no domain knowledge, just `Decimal?`/closures. Built for
/// `ROADMAP.md` D10/T10.3's right-holder percentage-share fields
/// (`performanceBroadcastShare`/`mechanicalRightsShare`, SPEC.md §4.4/§4.6),
/// used at two call sites per right-holder row across a `Cue`'s whole list —
/// extracted directly per `CONTRIBUTING.md` §3's rule of three, the same
/// trigger `GhostIntField` itself cites, rather than duplicating this
/// field-by-field.
///
/// **Binds through a `String` internally, never `TextField(_:value:format:)`
/// — this is a correctness requirement here, not just `GhostIntField`'s own
/// "show ghost text instead of a literal 0" reason.** SPEC.md §4.6 chose
/// `Decimal` specifically because it does exact base-10 arithmetic, so the
/// 100%-sum validation needs zero tolerance — but that guarantee only holds
/// if a `Decimal` value is ever *constructed* from an exact decimal
/// representation. `Decimal(_:)` from a `Double` literal is **not** exact
/// (`docs/REVIEW.md`'s D2 entry: `33.33` as a `Double`-routed literal prints
/// as `33.32999999999999488`) — a `TextField(value:format:.number)`-style
/// binding risks exactly this, since SwiftUI's numeric format styles
/// generally parse through a `Double`/`Decimal` bridging path, not
/// guaranteed to preserve every digit typed. Routing through this field's own
/// `String` binding and parsing with `Decimal(string:)` — which reads decimal
/// digits directly, with no `Double` involved at any point — is what keeps
/// SPEC.md §4.6's whole reason for choosing `Decimal` intact all the way from
/// the keystroke to the stored value. An unparseable string (a stray letter,
/// a trailing "-") leaves `value` at whatever it last successfully parsed to,
/// rather than silently coercing to `0` or a truncated guess.
public struct GhostDecimalField: View {
    private let placeholder: String
    @Binding private var value: Decimal?
    private let surface: Theme.Surface

    public init(placeholder: String, value: Binding<Decimal?>, surface: Theme.Surface = .primary) {
        self.placeholder = placeholder
        _value = value
        self.surface = surface
    }

    private var textBinding: Binding<String> {
        Binding(
            // `Decimal`'s own `description` — not `NSDecimalNumber`/`Double`
            // — formats directly from its internal decimal digits, so
            // displaying a value already round-trips exactly, same as
            // parsing it does below.
            get: { value.map { "\($0)" } ?? "" },
            set: { newText in
                let trimmed = newText.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    value = nil
                } else if let parsed = Decimal(string: trimmed) {
                    value = parsed
                }
                // An in-progress, not-yet-parseable string (e.g. a bare "-"
                // or "." typed mid-entry) is left as a no-op rather than
                // clearing `value` — the field's own displayed text (SwiftUI
                // keeps typed characters in a `TextField` independent of
                // this binding's `get`) still shows what was typed until it
                // either resolves to a real `Decimal` or is deleted.
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

#Preview("GhostDecimalField") {
    struct PreviewHost: View {
        @State private var value: Decimal? = Decimal(string: "33.33")
        var body: some View {
            GhostDecimalField(placeholder: "Share %", value: $value)
                .padding(Theme.Spacing.lg)
                .background(Theme.Surface.primary.background)
        }
    }
    return PreviewHost()
}
