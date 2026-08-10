import ACCore
import ACDesignSystem
import SwiftUI

/// The four `PostalAddress` fields (SPEC.md §4.5), used by `PersonEditorSheet`
/// (`Person.address`, optional) and `LabelEditorSheet` (`Label.address`,
/// required) — not by `SetupView` directly, since `Setup` has no
/// `PostalAddress` field of its own. Built alongside those two sheets
/// (`ROADMAP.md` D7/T7.3's commit), not T7.2's `SetupView` commit, despite
/// being listed under T7.2 in `ROADMAP.md`'s original file list — its real
/// consumers are T7.3's sheets; see `docs/DECISIONS.md`.
///
/// Takes plain `String` bindings, not a `PostalAddress` binding directly —
/// `PostalAddress`'s four fields are all non-optional `String`, so an empty
/// in-progress address (e.g. street filled in, city not yet) has no partial
/// `PostalAddress?` representation to bind to; the caller (`PersonEditorSheet`/
/// `LabelEditorSheet`) owns four separate `@State` strings and assembles a
/// `PostalAddress` only once all four are non-blank.
struct PostalAddressFields: View {
    @Binding var street: String
    @Binding var postalCode: String
    @Binding var city: String
    @Binding var country: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            GhostTextField(placeholder: "Street", text: $street)
            HStack(spacing: Theme.Spacing.sm) {
                GhostTextField(placeholder: "Postal Code", text: $postalCode)
                GhostTextField(placeholder: "City", text: $city)
            }
            GhostTextField(placeholder: "Country", text: $country)
        }
    }
}
