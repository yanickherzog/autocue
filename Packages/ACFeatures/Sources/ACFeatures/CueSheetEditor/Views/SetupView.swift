import ACCore
import ACDesignSystem
import SwiftUI

/// The Setup section's root content (`ROADMAP.md` D7/T7.2). Receives both
/// ViewModels as plain initializer parameters, per `CLAUDE.md`'s Dependency
/// Injection Pattern — never constructs or looks either up itself.
///
/// **Holds a local `draft: Setup` mirror, seeded once from
/// `viewModel.setup`.** `Setup`'s fields are all `let` (this codebase's
/// established convention for domain value types — see `DeleteRightHolder-
/// UseCase`'s doc comment), so SwiftUI's `$binding.field`-style dynamic
/// member lookup (which needs a `WritableKeyPath`) isn't available; every
/// field binding here goes through `Setup.updating(...)` instead via the
/// small `field`/`immediateField` helpers below. `draft` is never
/// overwritten from `viewModel.setup` after the initial seed — this View is
/// the sole place editing it for the lifetime of this screen instance, the
/// same "this window is the sole editor" reasoning `SetupViewModel`'s own
/// doc comment already establishes.
///
/// **Split across four files** (this one plus `SetupView+{Production,
/// Broadcast,Declaration}Section.swift`) — the single-file version exceeded
/// `CONTRIBUTING.md` §8's `SwiftLint` file-length/type-body-length
/// thresholds (roughly two dozen §4.2 fields is genuinely a lot of form UI).
/// Each extension file owns one of `SetupView`'s three logical sections; the
/// shared binding helpers (`field`/`immediateField`), party-field plumbing,
/// and `PartyField` stay here since all three sections use them.
public struct SetupView: View {
    @Bindable var viewModel: SetupViewModel
    let directoryViewModel: RightHolderDirectoryViewModel

    @State var draft: Setup
    @State var activePartyField: PartyField?
    @State var hasBroadcastDetails: Bool
    /// Set to open the `Producer`/`Director / Principal`/`Declarant` field's
    /// currently-resolved entry for editing — the displayed name itself is
    /// clickable, same "reuse the create sheet for editing too" pattern as
    /// the Collaborators section's roster rows and `PartyPickerView`'s own
    /// pencil-icon affordance. Which of these two gets set is determined by
    /// resolving the field's `Party` (`.person`/`.label`) in `beginEditing`
    /// below — `PartyResolver`'s `ResolvedParty` only carries display data,
    /// not the original `Person`/`Label`, so this looks the entry up
    /// directly by id instead of reusing that resolved value.
    @State private var personBeingEdited: Person?
    @State private var labelBeingEdited: ACCore.Label?

    public init(viewModel: SetupViewModel, directoryViewModel: RightHolderDirectoryViewModel) {
        _viewModel = Bindable(viewModel)
        self.directoryViewModel = directoryViewModel
        // Seeded from the ViewModel's placeholder empty Setup — `.task`
        // below re-seeds `draft` once, after `viewModel.load()` fetches the
        // real persisted value (`SetupViewModel`'s own doc comment explains
        // why the fetch can't happen synchronously here).
        _draft = State(initialValue: viewModel.setup)
        _hasBroadcastDetails = State(initialValue: viewModel.setup.broadcastDetails != nil)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                if viewModel.shouldShowMissingFieldsWarning {
                    missingFieldsBanner
                }
                productionSection
                Divider().overlay(Theme.Colors.dividerPrimary)
                collaboratorsSection
                Divider().overlay(Theme.Colors.dividerPrimary)
                broadcastSection
                Divider().overlay(Theme.Colors.dividerPrimary)
                declarationSection
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.Surface.primary.background)
        // See FixedAppearanceModifier's doc comment: native controls
        // (TextField's prompt, Picker's selected-value display, List's
        // background) don't respect this app's fixed non-adaptive palette
        // via .foregroundStyle() alone — confirmed via direct rendering
        // tests, not assumed.
        .fixedAppearance(for: .primary)
        .errorAlert(message: $viewModel.errorMessage)
        .task {
            await viewModel.load()
            // Re-seed once, now that the real persisted Setup has arrived —
            // never again after this (see SetupView's own doc comment on
            // why `draft` isn't kept live-synced with `viewModel.setup`).
            draft = viewModel.setup
            hasBroadcastDetails = viewModel.setup.broadcastDetails != nil
            await directoryViewModel.loadDirectory()
        }
        .onDisappear {
            let viewModel = viewModel
            Task { await viewModel.flushPendingSave() }
        }
        .sheet(item: $activePartyField) { partyField in
            PartyPickerView(
                directoryViewModel: directoryViewModel,
                onSelect: { party in
                    apply(party, to: partyField)
                    activePartyField = nil
                },
                onCancel: { activePartyField = nil }
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
        .sheet(item: $labelBeingEdited) { label in
            LabelEditorSheet(
                existing: label,
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

    var missingFieldsBanner: some View {
        Text("Missing: \(viewModel.missingRequiredFields.map(Self.displayName).joined(separator: ", "))")
            .font(Theme.Typography.font(.regular, size: 12))
            .foregroundStyle(Theme.Colors.accent)
    }

    // MARK: - Party fields

    func partyFieldRow(title: String, party: Party?, field: PartyField) -> some View {
        HStack {
            // `.medium`/full-opacity foreground — matches
            // `CollaboratorPersonBucket`/`CollaboratorLabelBucket`'s own
            // bucket-title styling exactly (`SetupView+CollaboratorsSection`)
            // rather than an independently-chosen dimmed style. Producer,
            // Director/Principal, and Declarant all render through this one
            // shared function, so fixing the style here — not per call site —
            // is what keeps all three, and the four roster bucket headers,
            // genuinely consistent rather than only visually similar.
            Text(title)
                .font(Theme.Typography.font(.medium, size: 13))
                .foregroundStyle(Theme.Surface.primary.foreground)
            Spacer()
            if let party, let displayName = resolvedDisplayName(for: party) {
                Button {
                    beginEditing(party)
                } label: {
                    Text(displayName)
                        .font(Theme.Typography.font(.regular, size: 13))
                        .foregroundStyle(Theme.Surface.primary.foreground)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            } else {
                // Ghost-text styled, matching the same de-emphasis convention
                // `GhostTextField`'s placeholder uses (`CLAUDE.md`'s Visual
                // Language) — an earlier version of this row showed a plain
                // "Not set" literal in full-strength foreground color, which
                // read as real content rather than an empty state.
                Text("No \(title) selected")
                    .font(Theme.Typography.font(.regular, size: 13))
                    .foregroundStyle(Theme.Colors.ghostTextPrimary)
            }
            // Only shown once a Party is actually set — `Setup.producer`/
            // `.directorOrPrincipal`/`.declarant` are all `Party?` and
            // legitimately support being unset, but there was previously no
            // way to get back to "Not set" once a value had been picked
            // (found in manual testing; the delete-guard blocking removal of
            // a still-*referenced* Person/Label is correct and separate from
            // this — clearing the field is what makes the Person/Label
            // unreferenced in the first place). Same `.plain`-button "✕"
            // pattern the Artists roster (`SetupView+CollaboratorsSection`)
            // already uses for its per-row remove action, applied to this
            // single-select field instead of a list row.
            if party != nil {
                Button {
                    clear(field)
                } label: {
                    Text("✕").foregroundStyle(Theme.Surface.primary.foreground.opacity(0.6))
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
            Button("Select") { activePartyField = field }
                .buttonStyle(SharpButtonStyle(emphasis: .secondary, surface: .primary))
        }
    }

    /// `nil` means "show the ghost-styled empty state" — covers both an
    /// actually-unset field and a `Party` reference that fails to resolve
    /// (e.g. a dangling id); there's nothing more informative to show for
    /// the latter without deeper investigation, and the two were already
    /// treated identically before this row grew a distinct ghost-text style.
    private func resolvedDisplayName(for party: Party?) -> String? {
        guard let party else { return nil }
        return PartyResolver.resolve(party, people: directoryViewModel.people, labels: directoryViewModel.labels)?
            .displayName
    }

    /// Resolves `party` to the actual `Person`/`Label` it references and
    /// opens the matching edit sheet — a no-op if it fails to resolve (the
    /// dangling-reference edge case `resolvedDisplayName` already treats as
    /// "nothing to show," so there's nothing valid to edit either).
    private func beginEditing(_ party: Party) {
        switch party {
        case let .person(id):
            personBeingEdited = directoryViewModel.people.first { $0.id == id }
        case let .label(id):
            labelBeingEdited = directoryViewModel.labels.first { $0.id == id }
        }
    }

    private func apply(_ party: Party, to field: PartyField) {
        switch field {
        case .declarant: draft = draft.updating(declarant: .some(party))
        }
        Task { await viewModel.updateImmediately(draft) }
    }

    /// Sets `field` back to `nil` — the double-optional `.some(nil)` argument
    /// is `Setup.updating(...)`'s established way to explicitly overwrite an
    /// optional field with `nil`, as opposed to the parameter's own default
    /// `nil` (meaning "leave unchanged"). Immediate save, same as `apply`:
    /// picking or clearing a Party is a discrete, complete action, not
    /// continuous typing.
    private func clear(_ field: PartyField) {
        switch field {
        case .declarant: draft = draft.updating(declarant: .some(nil))
        }
        Task { await viewModel.updateImmediately(draft) }
    }

    // MARK: - Binding helpers

    /// For continuous field-level edits — debounced.
    func field<Value>(
        _ get: @escaping (Setup) -> Value,
        _ update: @escaping (Setup, Value) -> Setup
    ) -> Binding<Value> {
        Binding(
            get: { get(draft) },
            set: { newValue in
                draft = update(draft, newValue)
                viewModel.updateDebounced(draft)
            }
        )
    }

    /// For discrete, complete actions (party picks, checkbox toggles) —
    /// immediate, per `SetupViewModel`'s save-timing rule.
    func immediateField<Value>(
        _ get: @escaping (Setup) -> Value,
        _ update: @escaping (Setup, Value) -> Setup
    ) -> Binding<Value> {
        Binding(
            get: { get(draft) },
            set: { newValue in
                draft = update(draft, newValue)
                Task { await viewModel.updateImmediately(draft) }
            }
        )
    }

    func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Theme.Typography.font(.medium, size: 15))
            .foregroundStyle(Theme.Surface.primary.foreground)
    }

    private static func displayName(_ field: SetupRequiredField) -> String {
        switch field {
        case .title: "Title"
        case .producer: "Producer*in"
        case .directorOrPrincipal: "Regisseur*in"
        case .productionRuntime: "Production Runtime"
        case .productionYear: "Production Year"
        case .productionTypes: "Production Types"
        case .declarant: "Declarant"
        }
    }
}

/// **Single-case now, deliberately — not an oversight.** `Producer`/
/// `Director` used to share this single-select `activePartyField`/
/// `partyFieldRow` mechanism with `Declarant`; they moved to their own
/// multi-entry `MultiPartyFieldBucket` (`SetupView+CollaboratorsSection.swift`)
/// once `Setup.producer`/`.directorOrPrincipal` became `[Party]` (`ROADMAP.md`
/// D7, later round — see `docs/DECISIONS.md`). `Declarant` alone is still a
/// genuinely single-valued field, so it keeps this mechanism rather than
/// each of the three getting a bespoke implementation.
enum PartyField: Identifiable, Hashable {
    case declarant

    var id: Self {
        self
    }
}
