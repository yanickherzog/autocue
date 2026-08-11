import ACCore
import ACDesignSystem
import SwiftUI

/// The Label bucket — lists `directoryViewModel.labels` whose
/// `intendedForLabelRoster` is `true` (`ACCore.Label.intendedForLabelRoster`'s
/// own doc comment), the exact `Person.intendedRoles` pattern
/// `CollaboratorPersonBucket` already establishes, applied to `Label`'s one
/// equivalent roster. **Not unfiltered** — an earlier version of this bucket
/// showed the *entire* project directory, which meant a `Label` created via
/// Producer*in's "+ New Company" (added to the shared directory *and* to
/// `Setup.producer`) also silently appeared here, never having been
/// selected for this bucket at all, while a `Label` created *from* this
/// bucket correctly never appeared under Producer*in (since `Setup.producer`
/// membership was already correctly filtered) — a real, confirmed
/// asymmetry, not a hypothetical. See `docs/DECISIONS.md`.
///
/// "Select" lets the user pick an existing `Label` — including one *not*
/// currently in this bucket, e.g. one created via Producer*in — which now
/// genuinely adds it here (`addToRoster`), or create a brand-new one via the
/// same shared picker, scoped to `.labelOnly`. This is the *only* way a
/// `Label` crosses into this bucket from elsewhere: a deliberate, explicit
/// selection, never an automatic side effect of being created or selected
/// somewhere else.
///
/// Extracted into its own file once `SetupView+CollaboratorsSection.swift`
/// exceeded `CONTRIBUTING.md` §8's `SwiftLint` file-length threshold — the
/// same reason `MultiPartyFieldBucket` was already extracted earlier this
/// Deliverable.
struct CollaboratorLabelBucket: View {
    let directoryViewModel: RightHolderDirectoryViewModel

    @State private var isShowingPicker = false
    /// See `CollaboratorPersonBucket.personBeingEdited`'s doc comment — same
    /// pattern, for `Label`.
    @State private var labelBeingEdited: ACCore.Label?

    private var labels: [ACCore.Label] {
        directoryViewModel.labels.filter(\.intendedForLabelRoster)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text("Label")
                    .font(Theme.Typography.font(.medium, size: 13))
                    .foregroundStyle(Theme.Surface.primary.foreground)
                Spacer()
                Button("Select") { isShowingPicker = true }
                    .buttonStyle(SharpButtonStyle(emphasis: .secondary, surface: .primary))
            }
            if labels.isEmpty {
                Text("No labels added yet.")
                    .font(Theme.Typography.font(.regular, size: 13))
                    .foregroundStyle(Theme.Colors.ghostTextPrimary)
            } else {
                ForEach(labels) { label in
                    HStack {
                        Button {
                            labelBeingEdited = label
                        } label: {
                            Text(label.name)
                                .font(Theme.Typography.font(.regular, size: 13))
                                .foregroundStyle(Theme.Surface.primary.foreground)
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                        Spacer()
                        // "✕" removes only this Label from *this bucket*
                        // (clears `intendedForLabelRoster`), never a real
                        // delete — same reasoning as `MultiPartyFieldBucket`'s
                        // own "✕" and `CollaboratorPersonBucket`'s "✕" role
                        // removal: a `Label` can be referenced from more than
                        // one place (Producer*in, a `Cue`), so removing it
                        // from this one bucket must never cascade into
                        // deleting the directory entry itself. Real deletion
                        // now lives only in the picker's own trash icon
                        // (`PartyPickerView`), which correctly still goes
                        // through `DeleteRightHolderUseCase`'s reference
                        // guard.
                        Button {
                            Task { await removeFromRoster(label) }
                        } label: {
                            Text("✕").foregroundStyle(Theme.Surface.primary.foreground.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingPicker) {
            PartyPickerView(
                directoryViewModel: directoryViewModel,
                scope: .labelOnly,
                showsLabelKindField: false,
                initialIntendedForLabelRoster: true,
                onSelect: { party in
                    guard case let .label(labelID) = party else { return }
                    isShowingPicker = false
                    Task { await addToRoster(labelID: labelID) }
                },
                onCancel: { isShowingPicker = false }
            )
        }
        .sheet(item: $labelBeingEdited) { label in
            LabelEditorSheet(
                existing: label,
                showsKindField: false,
                onSave: { edited in
                    let result = await directoryViewModel.saveLabel(edited)
                    if case .saved = result {
                        labelBeingEdited = nil
                    }
                    return result
                },
                onCancel: { labelBeingEdited = nil }
            )
        }
    }

    /// No-ops if `labelID` is already in this roster — covers both "the user
    /// picked an existing `Label` that's already here" and "the `Label` was
    /// *just* created via the picker's own '+ New Label' sheet, which
    /// already pre-filled `intendedForLabelRoster`" (avoids a redundant
    /// second write), the same pattern `CollaboratorPersonBucket.addRole`
    /// already establishes.
    private func addToRoster(labelID: ACCore.Label.ID) async {
        guard let label = directoryViewModel.labels.first(where: { $0.id == labelID }),
              !label.intendedForLabelRoster
        else {
            return
        }
        await directoryViewModel.saveLabel(Self.updating(label, intendedForLabelRoster: true))
    }

    private func removeFromRoster(_ label: ACCore.Label) async {
        await directoryViewModel.saveLabel(Self.updating(label, intendedForLabelRoster: false))
    }

    /// `Label`'s fields are all `let` — reconstruction via the memberwise
    /// initializer, the same pattern `CollaboratorPersonBucket.updating`
    /// already establishes for `Person`.
    private static func updating(_ label: ACCore.Label, intendedForLabelRoster: Bool) -> ACCore.Label {
        ACCore.Label(
            id: label.id,
            name: label.name,
            address: label.address,
            ipiNumber: label.ipiNumber,
            kind: label.kind,
            intendedForLabelRoster: intendedForLabelRoster
        )
    }
}
