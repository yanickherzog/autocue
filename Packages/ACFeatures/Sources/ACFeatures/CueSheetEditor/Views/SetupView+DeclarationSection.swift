import ACCore
import ACDesignSystem
import SwiftUI

/// `SetupView`'s "Declaration" section — additional-undeclared-works
/// tri-state, ISAN/SUISA registration numbers, declarant, declaration date.
/// See `SetupView`'s own doc comment for why this screen is split across
/// files.
///
/// **Deliberately does not show `AttachmentTypePicker`.** `attachmentTypes`
/// is optional per SPEC.md §4.2 ("informational flags only") and unused in
/// practice — hidden from the UI rather than removed from the domain model,
/// per `docs/DECISIONS.md`. Flagged alongside the other items already
/// queued for `ROADMAP.md` D11/T11.3's SUISA revalidation checkpoint, in
/// case the real form does need it after all.
///
/// **Two paired rows, not one field per line** — "Contains Additional
/// Undeclared Works"/ISAN Number share a row, then Declarant/Declaration
/// Date share a second row. `Declarant` stays its own distinct single-select
/// field here, deliberately **not** folded into the Artists section
/// (`SetupView+CollaboratorsSection.swift`) — it's "who is signing this
/// submission," a different role than a collaborator, unchanged by any of
/// this Deliverable's reorder rounds.
extension SetupView {
    var declarationSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionHeader("Declaration")
            HStack(spacing: Theme.Spacing.sm) {
                additionalWorksPicker
                    .frame(maxWidth: .infinity, alignment: .leading)
                GhostTextField(
                    placeholder: "ISAN Number",
                    text: field({ $0.isanNumber ?? "" }, { $0.updating(isanNumber: .some($1.isEmpty ? nil : $1)) })
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let suisaRegistrationNumber = draft.suisaRegistrationNumber {
                // Not user-entered (SPEC.md §4.2) — assigned by SUISA after
                // submission, so this is display-only, never an input field.
                HStack {
                    Text("SUISA Registration Number")
                        .font(Theme.Typography.font(.regular, size: 13))
                        .foregroundStyle(Theme.Surface.primary.foreground.opacity(0.6))
                    Spacer()
                    Text(suisaRegistrationNumber)
                        .font(Theme.Typography.font(.regular, size: 13))
                        .foregroundStyle(Theme.Surface.primary.foreground)
                }
            }
            HStack(spacing: Theme.Spacing.sm) {
                partyFieldRow(title: "Declarant", party: draft.declarant, field: .declarant)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // `GhostDateField`, not a native `DatePicker` — see that
                // component's own doc comment for why (AppKit's
                // `NSDatePicker` never adopts this app's custom typography,
                // the same "letter spacing" inconsistency flagged for
                // Sendedatum's date field applies equally here; fixed the
                // same way in both places, not just one, per this round's
                // request for consistency across every checkbox/date
                // control on this screen).
                GhostDateField(
                    placeholder: "Declaration Date",
                    date: field({ $0.declarationDate }, { $0.updating(declarationDate: $1) })
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    var additionalWorksPicker: some View {
        Picker(
            "Additional Undeclared Works",
            selection: immediateField(
                { $0.containsAdditionalUndeclaredWorks },
                { $0.updating(containsAdditionalUndeclaredWorks: $1) }
            )
        ) {
            Text("Yes").tag(AdditionalWorksDeclaration.yes)
            Text("No").tag(AdditionalWorksDeclaration.no)
            Text("Not Known").tag(AdditionalWorksDeclaration.notKnown)
        }
        .foregroundStyle(Theme.Surface.primary.foreground)
        .tint(Theme.Colors.accent)
    }
}
