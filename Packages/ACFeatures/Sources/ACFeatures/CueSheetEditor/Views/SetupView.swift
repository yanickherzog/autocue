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
                if !viewModel.missingRequiredFields.isEmpty {
                    missingFieldsBanner
                }
                productionSection
                Divider().overlay(Theme.Colors.dividerPrimary)
                broadcastSection
                Divider().overlay(Theme.Colors.dividerPrimary)
                declarationSection
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.Surface.primary.background)
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
    }

    var missingFieldsBanner: some View {
        Text("Missing: \(viewModel.missingRequiredFields.map(Self.displayName).joined(separator: ", "))")
            .font(Theme.Typography.font(.regular, size: 12))
            .foregroundStyle(Theme.Colors.accent)
    }

    // MARK: - Party fields

    func partyFieldRow(title: String, party: Party?, field: PartyField) -> some View {
        HStack {
            Text(title)
                .font(Theme.Typography.font(.regular, size: 13))
                .foregroundStyle(Theme.Surface.primary.foreground.opacity(0.6))
            Spacer()
            Text(resolvedDisplayName(for: party))
                .font(Theme.Typography.font(.regular, size: 13))
                .foregroundStyle(Theme.Surface.primary.foreground)
            Button("Select") { activePartyField = field }
                .buttonStyle(SharpButtonStyle(emphasis: .secondary, surface: .primary))
        }
    }

    private func resolvedDisplayName(for party: Party?) -> String {
        guard let party else { return "Not set" }
        return PartyResolver.resolve(party, people: directoryViewModel.people, labels: directoryViewModel.labels)?
            .displayName ?? "Not set"
    }

    private func apply(_ party: Party, to field: PartyField) {
        switch field {
        case .producer: draft = draft.updating(producer: .some(party))
        case .directorOrPrincipal: draft = draft.updating(directorOrPrincipal: .some(party))
        case .declarant: draft = draft.updating(declarant: .some(party))
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
        case .producer: "Producer"
        case .directorOrPrincipal: "Director / Principal"
        case .productionRuntime: "Production Runtime"
        case .productionYear: "Production Year"
        case .productionTypes: "Production Types"
        case .declarant: "Declarant"
        }
    }
}

enum PartyField: Identifiable, Hashable {
    case producer
    case directorOrPrincipal
    case declarant

    var id: Self {
        self
    }
}
