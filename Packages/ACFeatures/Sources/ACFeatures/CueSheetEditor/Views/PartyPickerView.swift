import ACCore
import ACDesignSystem
import SwiftUI

/// Lets the user pick an existing `Person`/`Label` from the project's
/// directory, or create a new one inline. Originally built only for
/// `Setup.producer`/`.directorOrPrincipal`/`.declarant` (`ROADMAP.md`
/// D7/T7.3); now the single "Select" entry point for every Party/role slot
/// in Setup — those three single-select fields *and* the Collaborators
/// section's Komponist*in/Arrangeur*in/Interpret*in/Label rosters
/// (`SetupView+CollaboratorsSection.swift`) — replacing what used to be a
/// separate "+ Add" (always-create-new) flow on the roster side. One
/// combined Person+Label list by default, not two separate pickers — the
/// SUISA form's own field language ("name, first name **or publishing
/// company**") treats them as interchangeable answers to the same question;
/// `scope` narrows this to one kind for the roster buckets, where only one
/// kind is ever a valid answer (see `PartyPickerScope`'s doc comment).
///
/// **Always shows the *entire* project directory, never filtered by
/// `Person.intendedRoles`.** A real person can hold more than one roster
/// role on the same `Project` (`Person.intendedRoles`' own doc comment) —
/// someone hinted as Komponist*in at creation time must still be selectable
/// from the Interpret*in bucket's picker. `intendedRoles` only ever affects
/// what a *newly created* `Person` is pre-filled with (`initialIntendedRole`,
/// passed through to `PersonEditorSheet`), never who's selectable.
///
/// Backed directly by `RightHolderDirectoryViewModel` (not plain closures,
/// unlike `PersonEditorSheet`/`LabelEditorSheet`) — this View's whole job
/// *is* presenting that ViewModel's directory and driving its create
/// methods, so there's no adapter-at-the-edge boundary to cross here.
struct PartyPickerView: View {
    let directoryViewModel: RightHolderDirectoryViewModel
    var scope: PartyPickerScope = .any
    /// Overrides every user-visible occurrence of the word "Label" in *this*
    /// picker instance (its own title, the "+ New Label" button, and the
    /// title of both the create and edit `LabelEditorSheet`s it presents) —
    /// never the underlying `ACCore.Label` type, and never anything outside
    /// this one picker instance. Defaults to `"Label"` (unchanged everywhere
    /// this picker is reached from the standalone Label roster bucket or
    /// Declarant). Producer*in passes `"Company"` instead — that picker
    /// refers to the same corporate-entity concept throughout its own
    /// `GhostTextField(placeholder: "Company Name", ...)` already, so "Label"
    /// there was the odd one out, not "Company." Irrelevant when
    /// `scope == .personOnly` (Regisseur*in, matching Komponist*in): no
    /// `Label`/Company UI is shown there at all, per SPEC.md §4.5 — a
    /// director is always a person, not a company. See `docs/DECISIONS.md`.
    var labelDisplayName = "Label"
    /// Forwarded to both `LabelEditorSheet`s this picker presents (create and
    /// pencil-edit) as `showsKindField`. `false` only for the standalone
    /// Label roster bucket (`scope == .labelOnly`) — see that property's own
    /// doc comment for why. Defaults to `true` (unchanged everywhere else).
    var showsLabelKindField = true
    /// Forwarded to both `LabelEditorSheet`s this picker presents as
    /// `newEntryDefaultKind` — see that property's doc comment. `nil`
    /// (default) everywhere except Producer*in's "Company" picker
    /// (`.productionCompany`).
    var newLabelDefaultKind: LabelKind?
    /// Pre-fills a newly-created `Person`'s `intendedRoles` (passed through
    /// to `PersonEditorSheet`) — irrelevant when `scope == .labelOnly`.
    var initialIntendedRole: PersonIntendedRole?
    /// Forwarded only to the "+ New Artist" creation sheet's
    /// `PersonEditorSheet` — never to the pencil-icon edit sheet, which
    /// always shows IPI-Nr regardless of this picker's own context. See
    /// `PersonEditorSheet.showsIPINumberField`'s doc comment. Defaults to
    /// `true` (unchanged everywhere except Producer*in/Regisseur*in's own
    /// picker, via `MultiPartyFieldBucket`).
    var showsIPINumberFieldOnCreate = true
    /// Forwarded only to the "+ New Artist" creation sheet's
    /// `PersonEditorSheet`, as `showsAddressField` — never to the
    /// pencil-icon edit sheet. `true` only for Regisseur*in's picker (via
    /// `MultiPartyFieldBucket`) — see `PersonEditorSheet.showsAddressField`'s
    /// doc comment for the full reasoning. Defaults to `false` (unchanged
    /// everywhere else, including Producer*in and Declarant).
    var showsAddressFieldOnCreate = false
    /// Drives `showsAddressField` for the pencil-icon **edit** sheet — keyed
    /// off the person's actual current `Setup.directorOrPrincipal`
    /// membership (`SetupView.isDirector(_:)`), not off which picker context
    /// this happens to be. Defaults to "never" for a call site that doesn't
    /// pass the real check (every picker instance that isn't reachable from
    /// `SetupView` itself would otherwise have no way to answer this). See
    /// `PersonEditorSheet.showsAddressField`'s doc comment for the full
    /// reasoning behind checking actual role membership instead of creation
    /// context for the edit path.
    var isCurrentDirector: (Person.ID) -> Bool = { _ in false }
    /// Forwarded only to the "+ New Label"/"+ New Company" creation sheet's
    /// `LabelEditorSheet`, as `initialIntendedForLabelRoster` — `true` only
    /// for the standalone Label roster bucket's own picker
    /// (`CollaboratorLabelBucket`). Defaults to `false` (unchanged
    /// everywhere else, including Producer*in's "+ New Company"). See
    /// `ACCore.Label.intendedForLabelRoster`'s own doc comment.
    var initialIntendedForLabelRoster = false
    let onSelect: (Party) -> Void
    let onCancel: () -> Void

    @State private var isShowingNewPersonSheet = false
    @State private var isShowingNewLabelSheet = false
    /// Set to open that entry for editing — the pencil icon next to each
    /// list row, distinct from tapping the row itself (which selects).
    /// `.sheet(item:)`, not a `Bool` flag: both `Person`/`Label` are already
    /// `Identifiable`, and this reads more clearly than a separate
    /// `isShowingEditSheet` kept in sync with a stored "which entry" value —
    /// same pattern `SetupView+CollaboratorsSection`'s roster rows use for
    /// their own, equivalent edit affordance.
    @State private var personBeingEdited: Person?
    @State private var labelBeingEdited: ACCore.Label?

    private var isDirectoryEmpty: Bool {
        switch scope {
        case .any: directoryViewModel.people.isEmpty && directoryViewModel.labels.isEmpty
        case .personOnly: directoryViewModel.people.isEmpty
        case .labelOnly: directoryViewModel.labels.isEmpty
        }
    }

    private var title: String {
        switch scope {
        case .any: "Select Artist or \(labelDisplayName)"
        case .personOnly: "Select Artist"
        case .labelOnly: "Select \(labelDisplayName)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(title)
                .font(Theme.Typography.font(.medium, size: 17))
                .foregroundStyle(Theme.Surface.primary.foreground)

            if isDirectoryEmpty {
                EmptyStateView(
                    systemImage: "person.crop.circle.badge.questionmark",
                    title: "No Entries Yet",
                    message: scope == .labelOnly ? "Create a new \(labelDisplayName) to get started." :
                        "Create a new Artist to get started.",
                    surface: .primary
                )
            } else {
                List {
                    if scope != .labelOnly {
                        ForEach(directoryViewModel.people) { person in
                            pickerRow(title: "\(person.firstName) \(person.lastName)") {
                                onSelect(.person(person.id))
                            } onEdit: {
                                personBeingEdited = person
                            } onDelete: {
                                Task { await directoryViewModel.deletePerson(person.id) }
                            }
                        }
                    }
                    if scope != .personOnly {
                        ForEach(directoryViewModel.labels) { label in
                            pickerRow(
                                title: label.name,
                                onSelect: { onSelect(.label(label.id)) },
                                onEdit: { labelBeingEdited = label },
                                onDelete: { Task { await directoryViewModel.deleteLabel(label.id) } }
                            )
                        }
                    }
                }
                .listStyle(.plain)
                // List paints its own native background material behind
                // rows on macOS, which a plain .background() on the List
                // does not override (the exact bug D6's ProjectLibraryView
                // already hit and fixed this same way) — without this, row
                // text renders on that native material instead of this
                // app's fixed white surface, unreadable under system Dark
                // Mode. Confirmed via a real rendered window, not assumed.
                .scrollContentBackground(.hidden)
                .background(Theme.Surface.primary.background)
                .frame(height: 220)
            }

            HStack {
                if scope != .labelOnly {
                    Button("+ New Artist") { isShowingNewPersonSheet = true }
                        .buttonStyle(SharpButtonStyle(emphasis: .secondary, surface: .primary))
                }
                if scope != .personOnly {
                    Button("+ New \(labelDisplayName)") { isShowingNewLabelSheet = true }
                        .buttonStyle(SharpButtonStyle(emphasis: .secondary, surface: .primary))
                }
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(SharpButtonStyle(emphasis: .secondary, surface: .primary))
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(width: 380)
        .background(Theme.Surface.primary.background)
        .fixedAppearance(for: .primary)
        // Deliberately does NOT call directoryViewModel.loadDirectory() on
        // appear. SetupView already loads it once, and every RightHolder-
        // DirectoryViewModel mutation (savePerson/saveLabel/deletePerson/
        // deleteLabel) updates people/labels in place — a second, redundant
        // subscription here raced against the "+ New Person" save flow: if
        // this task's own `for await ... break` happened to capture the
        // stream's pre-save snapshot (a real, confirmed ordering hazard,
        // not hypothetical — see docs/DECISIONS.md), it would silently
        // overwrite the optimistic post-save update, which is exactly what
        // produced "selecting closes the sheet but shows the old/blank
        // state until the picker is reopened."
        .sheet(isPresented: $isShowingNewPersonSheet) {
            PersonEditorSheet(
                existing: nil,
                initialIntendedRole: initialIntendedRole,
                showsIPINumberField: showsIPINumberFieldOnCreate,
                showsAddressField: showsAddressFieldOnCreate,
                onSave: { person in
                    let result = await directoryViewModel.savePerson(person)
                    if case .saved = result {
                        isShowingNewPersonSheet = false
                        onSelect(.person(person.id))
                    }
                    return result
                },
                onCancel: { isShowingNewPersonSheet = false }
            )
        }
        .sheet(isPresented: $isShowingNewLabelSheet) {
            LabelEditorSheet(
                existing: nil,
                displayName: labelDisplayName,
                showsKindField: showsLabelKindField,
                newEntryDefaultKind: newLabelDefaultKind,
                initialIntendedForLabelRoster: initialIntendedForLabelRoster,
                onSave: { label in
                    let result = await directoryViewModel.saveLabel(label)
                    if case .saved = result {
                        isShowingNewLabelSheet = false
                        onSelect(.label(label.id))
                    }
                    return result
                },
                onCancel: { isShowingNewLabelSheet = false }
            )
        }
        .sheet(item: $personBeingEdited) { person in
            PersonEditorSheet(
                existing: person,
                showsAddressField: isCurrentDirector(person.id),
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
        .sheet(item: $labelBeingEdited) { label in
            LabelEditorSheet(
                existing: label,
                displayName: labelDisplayName,
                showsKindField: showsLabelKindField,
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
        .errorAlert(message: blockedDeleteMessage)
    }

    /// One directory entry's row: tapping the name selects it (`onSelect`,
    /// this View's own `action:` parameter name would collide with the
    /// label above, hence `onSelect`/`onEdit` here); the pencil icon opens
    /// it for editing instead, via a separate tap target so the two actions
    /// can't be confused with each other. `onDelete`, when non-`nil`, adds a
    /// trailing trash icon — real deletion via `DeleteRightHolderUseCase`
    /// (through `RightHolderDirectoryViewModel.deletePerson`), the same
    /// guarded delete already exercised elsewhere on this screen, not a new
    /// mechanism. `nil` for `Label` rows — this round only adds the
    /// affordance for `Person`, per the request; `CollaboratorLabelBucket`
    /// already has its own delete action for `Label`, outside this picker.
    private func pickerRow(
        title: String,
        onSelect: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onDelete: (() -> Void)?
    ) -> some View {
        HStack {
            Button(action: onSelect) {
                Text(title)
                    .foregroundStyle(Theme.Surface.primary.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .pointingHandCursor()

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .foregroundStyle(Theme.Surface.primary.foreground.opacity(0.6))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()

            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(Theme.Surface.primary.foreground.opacity(0.6))
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
        }
    }

    /// Surfaces `RightHolderDirectoryViewModel.blockedDeleteLocations`
    /// (SPEC.md §4.12) as a readable message, the same pattern
    /// `SetupView+CollaboratorsSection`'s own `blockedDeleteMessage` already
    /// establishes for the roster buckets — reused here via
    /// `PartyReferenceLocation.displayName` (`SetupView.swift`) rather than a
    /// second, independently-maintained copy of the same switch.
    private var blockedDeleteMessage: Binding<String?> {
        Binding(
            get: {
                guard let locations = directoryViewModel.blockedDeleteLocations, !locations.isEmpty else {
                    return nil
                }
                let described = locations.map(\.displayName).joined(separator: ", ")
                return "Can't delete — still referenced by: \(described)."
            },
            set: { newValue in
                if newValue == nil {
                    directoryViewModel.clearBlockedDeleteLocations()
                }
            }
        )
    }
}

/// Which kind(s) of directory entry `PartyPickerView` lists as selectable,
/// and which "+ New ..." creation buttons it offers (the two always match —
/// unlike the displayed *wording* for "Label," which `labelDisplayName`
/// controls independently). `.any` (Declarant, Producer*in) offers both,
/// since SPEC.md draws no role restriction there; `.personOnly` (the four
/// roster buckets, and Regisseur*in — a director is always a person, per
/// SPEC.md §4.5) offers only `Person`; `.labelOnly` (the standalone Label
/// bucket) offers only `Label`.
enum PartyPickerScope: Equatable {
    case any
    case personOnly
    case labelOnly
}
