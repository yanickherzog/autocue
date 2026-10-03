import ACCore
import ACDesignSystem
import SwiftUI

/// Which `Setup` field a `MultiPartyFieldBucket`/`SetupView.addParty`/
/// `.removeParty` call is operating on — `Setup.producer`/
/// `.directorOrPrincipal` are the only two `[Party]` fields on `Setup`, so
/// this stays a plain two-case switch rather than a generic
/// `WritableKeyPath`-based accessor; `Setup`'s fields are all `let` (no
/// `WritableKeyPath` exists for them at all — see `SetupView`'s own doc
/// comment), and two cases don't yet justify more machinery than this.
///
/// Extracted into its own file, alongside `MultiPartyFieldBucket`, once
/// `SetupView+CollaboratorsSection.swift` exceeded `CONTRIBUTING.md` §8's
/// `SwiftLint` file-length threshold — the same reason `SetupView` itself
/// was already split across four files.
enum MultiPartyField {
    case producer
    case directorOrPrincipal

    func parties(in setup: Setup) -> [Party] {
        switch self {
        case .producer: setup.producer
        case .directorOrPrincipal: setup.directorOrPrincipal
        }
    }

    func updating(_ setup: Setup, parties: [Party]) -> Setup {
        switch self {
        case .producer: setup.updating(producer: parties)
        case .directorOrPrincipal: setup.updating(directorOrPrincipal: parties)
        }
    }
}

/// A multi-entry `Party` row-list — backs `Setup.producer`/
/// `.directorOrPrincipal` (`ROADMAP.md` D7, later round). Deliberately
/// styled and structured identically to `CollaboratorPersonBucket`/
/// `CollaboratorLabelBucket` (`SetupView+CollaboratorsSection.swift`; same
/// title styling, same ghost-text empty state, same per-row
/// name-button-plus-"✕" layout, same "Select" picker affordance) — an
/// explicit requirement that all six Artist categories render identically,
/// not just look similar.
///
/// **Producer*in and Regisseur*in use this same component with genuinely
/// different `scope`, not just different labels — confirmed directly, not
/// assumed.** Producer*in: `scope: .any` — a producer can be a `Person` or a
/// `Label` (production company), per SPEC.md §4.5's "name, first name **or
/// publishing company**" field language, so its picker keeps full "+ New
/// Person"/"+ New Label" (worded "Company" via `labelDisplayName`, below)
/// creation. Regisseur*in: `scope: .personOnly`, matching Komponist*in
/// exactly — a director is always a person, so no Label/Company concept
/// appears in that picker at all, not even for selecting an already-existing
/// one. See `docs/DECISIONS.md`.
///
/// **"✕" removes only this one `Party` from the list, not the underlying
/// `Person`/`Label` from the directory** — same reasoning
/// `CollaboratorPersonBucket`'s own "✕" doc comment already establishes: a
/// `Party` can be referenced from more than one place (another role bucket,
/// the other of Producer/Director, a `Cue`), so removing it from *this*
/// list must never cascade into deleting the directory entry itself.
struct MultiPartyFieldBucket: View {
    let title: String
    let emptyStateText: String
    let parties: [Party]
    let directoryViewModel: RightHolderDirectoryViewModel
    var scope: PartyPickerScope = .any
    /// Forwarded to the picker's own `labelDisplayName` — see that
    /// property's doc comment. Irrelevant when `scope == .personOnly`
    /// (Regisseur*in): no Label/Company UI is shown there at all.
    var labelDisplayName = "Label"
    /// Forwarded to the picker's own `newLabelDefaultKind` — see that
    /// property's doc comment. `.productionCompany` for Producer*in;
    /// irrelevant when `scope == .personOnly` (Regisseur*in).
    var newLabelDefaultKind: LabelKind?
    /// Forwarded to the picker's own `showsIPINumberFieldOnCreate` — `false`
    /// for both Producer*in and Regisseur*in (IPI numbers are relevant to
    /// SUISA-registered musicians, not companies/directors), unlike every
    /// other `labelDisplayName`/`newLabelDefaultKind`-style parameter on
    /// this type, which genuinely differs between the two. See
    /// `PersonEditorSheet.showsIPINumberField`'s doc comment.
    var showsIPINumberFieldOnCreate = true
    /// Forwarded straight to the picker's own
    /// `promptsForMissingAddressRole` — see that property's doc comment.
    /// `"Director"` for Regisseur*in's instance; `nil` (default,
    /// unchanged) for Producer*in — a Producer is almost always a `Label`,
    /// whose address is already always-required via "+ New Company", so the
    /// one real gap this mechanism exists for is Regisseur*in's own,
    /// `Person`-only picker.
    var promptsForMissingAddressRole: String?
    let onAdd: (Party) -> Void
    let onRemove: (Party) -> Void

    @State private var isShowingPicker = false
    /// See `CollaboratorPersonBucket.personBeingEdited`'s doc comment — same
    /// pattern, self-contained per bucket instance rather than shared with
    /// `SetupView`'s own `Declarant`-specific edit state.
    @State private var personBeingEdited: Person?
    @State private var labelBeingEdited: ACCore.Label?
    /// Set from `PartyPickerView.onPersonSelectedNeedingAddress` — presents
    /// `PersonAddressPromptSheet`. **Lives here, not on the internal
    /// `PartyPickerView` itself** — selecting a party dismisses that
    /// picker's own sheet (`isShowingPicker = false`, below) in the same
    /// call, so a sheet hosted on the picker's own body would be torn down
    /// along with it before the user could use it, a real, confirmed bug
    /// (`docs/DECISIONS.md`, 2026-10-03). This bucket itself is a
    /// persistent row in the Setup screen, not something dismissed on
    /// selection, so hosting it here is what actually keeps it on screen.
    @State private var personNeedingAddressPrompt: Person?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text(title)
                    .font(Theme.Typography.font(.medium, size: 13))
                    .foregroundStyle(Theme.Surface.primary.foreground)
                Spacer()
                Button("Select") { isShowingPicker = true }
                    .buttonStyle(SharpButtonStyle(emphasis: .secondary, surface: .primary))
            }
            if parties.isEmpty {
                Text(emptyStateText)
                    .font(Theme.Typography.font(.regular, size: 13))
                    .foregroundStyle(Theme.Colors.ghostTextPrimary)
            } else {
                ForEach(parties, id: \.self) { party in
                    HStack {
                        Button {
                            beginEditing(party)
                        } label: {
                            Text(displayName(for: party))
                                .font(Theme.Typography.font(.regular, size: 13))
                                .foregroundStyle(Theme.Surface.primary.foreground)
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                        Spacer()
                        Button {
                            onRemove(party)
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
                scope: scope,
                labelDisplayName: labelDisplayName,
                newLabelDefaultKind: newLabelDefaultKind,
                showsIPINumberFieldOnCreate: showsIPINumberFieldOnCreate,
                promptsForMissingAddressRole: promptsForMissingAddressRole,
                onPersonSelectedNeedingAddress: { person in personNeedingAddressPrompt = person },
                onSelect: { party in
                    isShowingPicker = false
                    onAdd(party)
                },
                onCancel: { isShowingPicker = false }
            )
        }
        .sheet(item: $personBeingEdited) { person in
            PersonEditorSheet(
                existing: person,
                onSave: { edited in
                    let result = await directoryViewModel.savePerson(edited)
                    if case .saved = result {
                        personBeingEdited = nil
                    }
                    return result
                },
                onCancel: { personBeingEdited = nil }
            )
        }
        .sheet(item: $personNeedingAddressPrompt) { person in
            PersonAddressPromptSheet(
                person: person,
                roleDescription: promptsForMissingAddressRole ?? "",
                onSave: { edited in
                    let result = await directoryViewModel.savePerson(edited)
                    if case .saved = result {
                        personNeedingAddressPrompt = nil
                    }
                    return result
                },
                onSkip: { personNeedingAddressPrompt = nil }
            )
        }
        .sheet(item: $labelBeingEdited) { label in
            LabelEditorSheet(
                existing: label,
                displayName: labelDisplayName,
                newEntryDefaultKind: newLabelDefaultKind,
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

    /// `nil` only if `party` fails to resolve (a dangling reference) — there
    /// is nothing more informative to show in that case, the same fallback
    /// `SetupView.resolvedDisplayName` uses for the single-select fields.
    private func displayName(for party: Party) -> String {
        PartyResolver.resolve(party, people: directoryViewModel.people, labels: directoryViewModel.labels)?
            .displayName ?? "Unknown"
    }

    private func beginEditing(_ party: Party) {
        switch party {
        case let .person(id):
            personBeingEdited = directoryViewModel.people.first { $0.id == id }
        case let .label(id):
            labelBeingEdited = directoryViewModel.labels.first { $0.id == id }
        }
    }
}
