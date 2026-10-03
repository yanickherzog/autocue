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
    /// Non-`nil` names the role (e.g. `"Declarant"`, `"Director"`) this
    /// picker is filling — when set, selecting (or creating-then-selecting)
    /// a `Person` whose `address` is `nil` calls `onPersonSelectedNeedingAddress`
    /// instead of presenting anything itself. `nil` (default) everywhere a
    /// role doesn't require an address — Producer*in (almost always a
    /// `Label`, whose address is already always-required) and the four
    /// roster buckets (ordinary collaborators never need one).
    ///
    /// **Real, confirmed bug fixed 2026-10-03 (`docs/DECISIONS.md`): this
    /// picker does NOT present `PersonAddressPromptSheet` itself, even
    /// though it owns the logic that decides whether to.** An earlier
    /// version did — a `.sheet(item:)` hosted directly on this View's own
    /// body — and it looked right in code review and passed every
    /// reasoning pass. It was wrong: `select(_:)` calls `onSelect(party)`
    /// *first*, and every real caller's `onSelect` closure dismisses this
    /// very picker's own hosting sheet (`activePartyField = nil` in
    /// `SetupView`, `isShowingPicker = false` in `MultiPartyFieldBucket`) —
    /// so the address prompt was being presented from a View that was
    /// *simultaneously being torn down*. Confirmed with real `NSLog`
    /// instrumentation and a live `log stream` capture, not just re-reading
    /// the code: the prompt's `onAppear` genuinely fired in every case
    /// (contradicting an initial bug report that it "never appeared" for
    /// one of the two selection paths — it did, briefly), followed by
    /// `onDisappear` roughly 0.8–1.1 seconds later with no corresponding
    /// Save/Skip in between — the exact duration of the parent picker's own
    /// dismiss animation completing, which tore the nested sheet down with
    /// it. The fix: the caller (the View that actually survives selection)
    /// owns the prompt's state and `.sheet` modifier; this picker only ever
    /// reports the need for one.
    var promptsForMissingAddressRole: String?
    /// Called from `select(_:)` instead of presenting anything here — see
    /// `promptsForMissingAddressRole`'s own doc comment for why ownership
    /// moved to the caller. `nil` (default) wherever
    /// `promptsForMissingAddressRole` is also `nil`; every real caller that
    /// sets the role also supplies this.
    var onPersonSelectedNeedingAddress: ((Person) -> Void)?
    /// Forwarded only to the "+ New Label"/"+ New Company" creation sheet's
    /// `LabelEditorSheet`, as `initialIntendedForLabelRoster` — `true` only
    /// for the standalone Label roster bucket's own picker
    /// (`CollaboratorLabelBucket`). Defaults to `false` (unchanged
    /// everywhere else, including Producer*in's "+ New Company"). See
    /// `ACCore.Label.intendedForLabelRoster`'s own doc comment.
    var initialIntendedForLabelRoster = false
    /// Hides "+ New Artist"/"+ New \(labelDisplayName)" entirely when
    /// `false` — this picker then only ever lets the user choose from the
    /// project's *existing* directory, never create a new, unconnected
    /// entry inline. `true` (default, unchanged everywhere else). `false`
    /// only for Declarant's own picker (`SetupView.swift`) — a deliberate,
    /// reversible product scope decision (`docs/DECISIONS.md`, 2026-10-03,
    /// same pattern as D10's hidden reorder/"+ Add Cue" features): AutoCue
    /// targets a rights-holder declaring their own cue sheet, so Declarant
    /// should always resolve to someone already entered elsewhere in the
    /// project (typically a composer), never a brand-new, unconnected
    /// entry created on the spot. Director, Producer, and every roster
    /// bucket keep their creation buttons unchanged — this is Declarant-
    /// specific only, not a general restriction on this picker.
    var allowsCreatingNewEntries = true
    let onSelect: (Party) -> Void
    let onCancel: () -> Void

    // Not `private` — `PartyPickerView+Sheets.swift`'s extension (the
    // `.sheet` modifier chain, split out once this file exceeded
    // `CONTRIBUTING.md` §8's `SwiftLint` file-length threshold) needs direct
    // access, the same "drop `private` for cross-file same-type access"
    // convention `SetupView`'s own split-out section files already
    // establish for `draft`/`activePartyField`.
    @State var isShowingNewPersonSheet = false
    @State var isShowingNewLabelSheet = false
    /// Set to open that entry for editing — the pencil icon next to each
    /// list row, distinct from tapping the row itself (which selects).
    /// `.sheet(item:)`, not a `Bool` flag: both `Person`/`Label` are already
    /// `Identifiable`, and this reads more clearly than a separate
    /// `isShowingEditSheet` kept in sync with a stored "which entry" value —
    /// same pattern `SetupView+CollaboratorsSection`'s roster rows use for
    /// their own, equivalent edit affordance.
    @State var personBeingEdited: Person?
    @State var labelBeingEdited: ACCore.Label?

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

    /// "Create a new ... to get started" only makes sense when creation is
    /// actually offered — `allowsCreatingNewEntries == false` (Declarant's
    /// picker) shows a plain "nothing here yet" message instead, since
    /// there's no "+ New ..." button on screen for it to point at.
    private var emptyStateMessage: String {
        guard allowsCreatingNewEntries else {
            return scope == .labelOnly ? "No \(labelDisplayName) entries in this project yet." :
                "No Artist entries in this project yet."
        }
        return scope == .labelOnly ? "Create a new \(labelDisplayName) to get started." :
            "Create a new Artist to get started."
    }

    /// `partyPickerSheets(_:)` (`PartyPickerView+Sheets.swift`) wraps
    /// `mainContent` with every create/edit `.sheet` this picker presents —
    /// split into its own file once this one exceeded `CONTRIBUTING.md`
    /// §8's `SwiftLint` file-length threshold.
    var body: some View {
        partyPickerSheets(mainContent)
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(title)
                .font(Theme.Typography.font(.medium, size: 17))
                .foregroundStyle(Theme.Surface.primary.foreground)

            if isDirectoryEmpty {
                EmptyStateView(
                    systemImage: "person.crop.circle.badge.questionmark",
                    title: "No Entries Yet",
                    message: emptyStateMessage,
                    surface: .primary
                )
            } else {
                List {
                    if scope != .labelOnly {
                        ForEach(directoryViewModel.people) { person in
                            pickerRow(title: "\(person.firstName) \(person.lastName)") {
                                select(person)
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
                if allowsCreatingNewEntries {
                    if scope != .labelOnly {
                        Button("+ New Artist") { isShowingNewPersonSheet = true }
                            .buttonStyle(SharpButtonStyle(emphasis: .secondary, surface: .primary))
                    }
                    if scope != .personOnly {
                        Button("+ New \(labelDisplayName)") { isShowingNewLabelSheet = true }
                            .buttonStyle(SharpButtonStyle(emphasis: .secondary, surface: .primary))
                    }
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
    }

    /// Completes selecting `person` (`onSelect`, same as selecting a
    /// `Label` always does directly) and, if `promptsForMissingAddressRole`
    /// is set and `person` has no address yet, reports that via
    /// `onPersonSelectedNeedingAddress` — covering both real paths that
    /// produce a selected `Person` here: picking one from the list, and
    /// successfully creating a brand-new one (whose own `onSave` closure,
    /// in `PartyPickerView+Sheets.swift`, calls this too). **Deliberately
    /// does not present anything itself** — see
    /// `promptsForMissingAddressRole`'s own doc comment for the real,
    /// confirmed bug this fixes. Not `private` — the "+ New Person" sheet's
    /// `onSave` closure, in the `+Sheets.swift` split, calls this directly.
    func select(_ person: Person) {
        onSelect(.person(person.id))
        if promptsForMissingAddressRole != nil, person.address == nil {
            onPersonSelectedNeedingAddress?(person)
        }
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
    /// second, independently-maintained copy of the same switch. Not
    /// `private` — `PartyPickerView+Sheets.swift`'s `.errorAlert` uses it.
    var blockedDeleteMessage: Binding<String?> {
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
