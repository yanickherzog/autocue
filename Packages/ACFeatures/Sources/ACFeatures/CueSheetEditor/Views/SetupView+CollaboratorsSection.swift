import ACCore
import ACDesignSystem
import SwiftUI

/// `SetupView`'s "Artists" section (displayed title — the Swift identifiers
/// in this file stay `Collaborators*`/`collaboratorsSection`, a
/// display-label-only rename, same precedent as the "Person" → "Artist"
/// individual-entry rename elsewhere on this screen; see `docs/DECISIONS.md`)
/// — the project-scoped right-holder directory (`ROADMAP.md` D7/T7.3).
/// Organized into six identically-styled rows: the four
/// `PersonIntendedRole`/`Label` roster buckets matching the original product
/// brief (Komponist*in, Arrangeur*in, Interpret*in, Label), then
/// `Setup.producer`/`.directorOrPrincipal`'s own multi-entry rows, in that
/// order. See `SetupView`'s own doc comment for why this screen is split
/// across files.
///
/// **`Setup.producer`/`.directorOrPrincipal` are `[Party]` — one or more,
/// not at most one — reversing an earlier, explicitly-confirmed decision
/// that they stay single-valued.** Requested directly, with the earlier
/// decision named and its reasoning re-examined, not silently overridden;
/// see `docs/DECISIONS.md` for the full record of the reversal. Still kept
/// as their own distinct `Setup`-level fields, **not** folded into the
/// `PersonIntendedRole` roster mechanism the other four buckets use —
/// `PersonIntendedRole` is `Person`-only, and Producer/Director must still
/// be able to reference a `Label` (a production company), per the SUISA
/// form's own "name, first name **or publishing company**" field language
/// (SPEC.md §4.5); promoting them into `PersonIntendedRole` cases would
/// silently drop that capability. Instead, `MultiPartyFieldBucket` (below)
/// gives them the *same visual row behavior* as the four roster buckets —
/// per an explicit follow-up request that all six render identically — while
/// keeping their `[Party]` storage entirely separate from
/// `Person.intendedRoles`. `Declarant` is *not* included in this move — it
/// stays in the Declaration section, a distinct "who is signing this
/// submission" role rather than a collaborator, reconfirmed unchanged when
/// this reversal was made. See `docs/DECISIONS.md`.
///
/// **Every bucket's "+ Add" was replaced with "Select"** — the same
/// `PartyPickerView` picker Declarant already uses, scoped to
/// `.personOnly`/`.labelOnly`/`.any`. An earlier version of this section only
/// ever let a bucket create a brand-new `Person`/`Label`, with no way to
/// reuse an existing directory entry under a second role — confirmed as a
/// real UX gap once a `Person` needed to be both Komponist*in *and*
/// Interpret*in on the same `Project`. See `docs/DECISIONS.md`.
extension SetupView {
    var collaboratorsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionHeader("Artists")
            CollaboratorPersonBucket(
                title: "Komponist*in",
                role: .composer,
                emptyStateText: "No composers added yet.",
                directoryViewModel: directoryViewModel
            )
            CollaboratorPersonBucket(
                title: "Arrangeur*in",
                role: .arranger,
                emptyStateText: "No arrangers added yet.",
                directoryViewModel: directoryViewModel
            )
            CollaboratorPersonBucket(
                title: "Interpret*in",
                role: .performer,
                emptyStateText: "No performers added yet.",
                directoryViewModel: directoryViewModel
            )
            CollaboratorLabelBucket(directoryViewModel: directoryViewModel)
            MultiPartyFieldBucket(
                title: "Producer*in",
                emptyStateText: "No producers added yet.",
                parties: draft.producer,
                directoryViewModel: directoryViewModel,
                scope: .any,
                labelDisplayName: "Company",
                newLabelDefaultKind: .productionCompany,
                onAdd: { party in addParty(party, to: .producer) },
                onRemove: { party in removeParty(party, from: .producer) }
            )
            MultiPartyFieldBucket(
                title: "Regisseur*in",
                emptyStateText: "No directors added yet.",
                parties: draft.directorOrPrincipal,
                directoryViewModel: directoryViewModel,
                scope: .personOnly,
                onAdd: { party in addParty(party, to: .directorOrPrincipal) },
                onRemove: { party in removeParty(party, from: .directorOrPrincipal) }
            )
        }
        .errorAlert(message: blockedDeleteMessage)
    }

    /// No-ops if `party` is already in `field`'s list — same
    /// duplicate-prevention convention `CollaboratorPersonBucket.addRole`
    /// already establishes, applied to a plain array membership check
    /// instead of `Set`/`intendedRoles` membership, since `[Party]` doesn't
    /// enforce uniqueness itself (unlike `Set<PersonIntendedRole>`).
    /// Immediate save: picking a Party is a discrete, complete action, the
    /// same timing `apply(_:to:)` already uses for `Declarant`.
    private func addParty(_ party: Party, to field: MultiPartyField) {
        let current = field.parties(in: draft)
        guard !current.contains(party) else { return }
        draft = field.updating(draft, parties: current + [party])
        Task { await viewModel.updateImmediately(draft) }
    }

    private func removeParty(_ party: Party, from field: MultiPartyField) {
        let current = field.parties(in: draft)
        draft = field.updating(draft, parties: current.filter { $0 != party })
        Task { await viewModel.updateImmediately(draft) }
    }

    /// Surfaces `RightHolderDirectoryViewModel.blockedDeleteLocations`
    /// (SPEC.md §4.12) as a readable message — one place for all four
    /// buckets' delete attempts, since they share one `directoryViewModel`.
    private var blockedDeleteMessage: Binding<String?> {
        Binding(
            get: {
                guard let locations = directoryViewModel.blockedDeleteLocations, !locations.isEmpty else {
                    return nil
                }
                let described = locations.map(Self.describe).joined(separator: ", ")
                return "Can't delete — still referenced by: \(described)."
            },
            set: { newValue in
                if newValue == nil {
                    directoryViewModel.clearBlockedDeleteLocations()
                }
            }
        )
    }

    private static func describe(_ location: PartyReferenceLocation) -> String {
        switch location {
        case .setupProducer: "Producer*in"
        case .setupDirectorOrPrincipal: "Regisseur*in"
        case .setupDeclarant: "Declarant"
        case .settingsDefaultDeclarant: "Default Declarant (Settings)"
        case .cueRightHolder: "a Cue's right-holder list"
        }
    }
}

/// One Komponist*in/Arrangeur*in/Interpret*in bucket — lists
/// `directoryViewModel.people` whose `intendedRoles` contains this bucket's
/// `PersonIntendedRole`, and lets the user either pick an existing `Person`
/// from the *entire* project directory (never filtered by role — see
/// `PartyPickerView`'s doc comment) or create a brand-new one, both via the
/// shared "Select" picker.
///
/// **"✕" removes only this one role, not the whole `Person`.** Since a
/// `Person` can now belong to more than one bucket at once, deleting them
/// entirely from a single row would silently remove them from every other
/// bucket they're also in — confirmed as the wrong default via a direct
/// question, not assumed. If removing this role empties their
/// `intendedRoles` entirely, they simply stop appearing in any roster bucket
/// while remaining in the directory (still selectable/reusable elsewhere,
/// e.g. as Producer) — there is currently no separate "delete this Person
/// from the directory entirely" action from this section; that would be a
/// new, explicit affordance for a future pass, not implied by this one.
private struct CollaboratorPersonBucket: View {
    let title: String
    let role: PersonIntendedRole
    /// Ghost-styled placeholder shown when this bucket has no `Person`
    /// added yet — same `Theme.Colors.ghostTextPrimary` de-emphasis
    /// convention `partyFieldRow`'s own "No {field} selected" empty state
    /// and `GhostTextField`'s placeholder text already use. An earlier
    /// version of this bucket showed nothing at all when empty, with no
    /// visual hint the row was intentionally blank rather than broken.
    let emptyStateText: String
    let directoryViewModel: RightHolderDirectoryViewModel

    @State private var isShowingPicker = false
    /// Set to open that `Person` for editing — a roster row's name is
    /// directly clickable, per the same "reuse the create sheet for editing
    /// too" pattern `PartyPickerView`'s own pencil-icon edit affordance
    /// uses. `.sheet(item:)`, not a second `Bool` flag: `Person` is already
    /// `Identifiable`, and this reads more clearly than a separate
    /// `isShowingEditSheet` kept in sync with a stored "which person" value.
    @State private var personBeingEdited: Person?

    private var people: [Person] {
        directoryViewModel.people.filter { $0.intendedRoles.contains(role) }
    }

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
            if people.isEmpty {
                Text(emptyStateText)
                    .font(Theme.Typography.font(.regular, size: 13))
                    .foregroundStyle(Theme.Colors.ghostTextPrimary)
            } else {
                ForEach(people) { person in
                    HStack {
                        Button {
                            personBeingEdited = person
                        } label: {
                            Text("\(person.firstName) \(person.lastName)")
                                .font(Theme.Typography.font(.regular, size: 13))
                                .foregroundStyle(Theme.Surface.primary.foreground)
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                        Spacer()
                        Button {
                            Task { await removeRole(from: person) }
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
                scope: .personOnly,
                initialIntendedRole: role,
                onSelect: { party in
                    guard case let .person(personID) = party else { return }
                    isShowingPicker = false
                    Task { await addRole(toPersonID: personID) }
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
    }

    /// No-ops if `personID` already has `role` — covers both "the user
    /// picked an existing person who's already in this bucket" (the
    /// duplicate-prevention this whole feature exists for) and "the person
    /// was *just* created via the picker's own '+ New Person' sheet, which
    /// already pre-filled this exact role" (avoids a redundant second
    /// write).
    private func addRole(toPersonID personID: Person.ID) async {
        guard let person = directoryViewModel.people.first(where: { $0.id == personID }),
              !person.intendedRoles.contains(role)
        else {
            return
        }
        await directoryViewModel.savePerson(Self.updating(person, intendedRoles: person.intendedRoles.union([role])))
    }

    private func removeRole(from person: Person) async {
        await directoryViewModel.savePerson(Self.updating(
            person,
            intendedRoles: person.intendedRoles.subtracting([role])
        ))
    }

    /// `Person`'s fields are all `let` — reconstruction via the memberwise
    /// initializer, same pattern `DeleteRightHolderUseCase.replacing` and
    /// `SetupView.field`/`.immediateField` already establish for their own
    /// `let`-only domain types.
    private static func updating(_ person: Person, intendedRoles: Set<PersonIntendedRole>) -> Person {
        Person(
            id: person.id,
            firstName: person.firstName,
            lastName: person.lastName,
            ipiNumber: person.ipiNumber,
            address: person.address,
            email: person.email,
            swissPerformNumber: person.swissPerformNumber,
            intendedRoles: intendedRoles
        )
    }
}

/// The Label bucket — no `intendedRoles` concept (there's only one kind of
/// `Label` entry, so every `Label` in the directory already belongs here
/// unconditionally); "Select" lets the user pick an existing `Label` (a
/// no-op beyond dismissing, since it's already listed below) or create a
/// brand-new one, via the same shared picker the Person buckets use, scoped
/// to `.labelOnly`.
private struct CollaboratorLabelBucket: View {
    let directoryViewModel: RightHolderDirectoryViewModel

    @State private var isShowingPicker = false
    /// See `CollaboratorPersonBucket.personBeingEdited`'s doc comment — same
    /// pattern, for `Label`.
    @State private var labelBeingEdited: ACCore.Label?

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
            if directoryViewModel.labels.isEmpty {
                Text("No labels added yet.")
                    .font(Theme.Typography.font(.regular, size: 13))
                    .foregroundStyle(Theme.Colors.ghostTextPrimary)
            } else {
                ForEach(directoryViewModel.labels) { label in
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
                        Button {
                            Task { await directoryViewModel.deleteLabel(label.id) }
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
                onSelect: { _ in isShowingPicker = false },
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
}
