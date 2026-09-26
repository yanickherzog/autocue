import ACCore
import ACDesignSystem
import SwiftUI

/// Per-cue right-holder assignment and share entry (`ROADMAP.md` D10/T10.3,
/// SPEC.md §4.4/§4.6) — embedded inline in `CueRowDetailView`'s sheet, not
/// presented as a second, nested sheet of its own (avoids sheet-on-sheet
/// stacking on macOS). Reuses the project's existing `PartyPickerView`/
/// `RightHolderDirectoryViewModel` for party assignment rather than building
/// a second picker, per `CLAUDE.md`'s Reusable Component Philosophy.
///
/// **Purely local — no `CueDetectionReviewViewModel`, no async, no
/// debounce, no clamping.** The original version of this view wrote every
/// field edit through the ViewModel immediately/debounced, mid-edit. Per
/// direct instruction (`ROADMAP.md` D10, second round), a live "does this
/// pool still sum to ≤100%" check that briefly existed alongside that design
/// clamped/rejected keystrokes the moment a pool was already at or over
/// 100% — the fix is to make the whole editing session a single local,
/// freely-editable `Binding<[CueRightHolder]>` (`CueRowDetailView`'s own
/// `@State`), with nothing checked or written until "Done" commits it in one
/// shot. This view is now a plain, synchronous value-type editor over that
/// binding — previewable and testable with zero ViewModel/async knowledge.
///
/// **Rows are identified by their position in `rightHolders`, not a stable
/// `id`** — `CueRightHolder` deliberately has none (SPEC.md §4.4); see this
/// project's own precedent for exactly this shape, `Setup.broadcastDetails`.
struct CueRightHolderEditorView: View {
    @Binding var rightHolders: [CueRightHolder]
    let isArrangementOfProtectedOriginal: Bool
    let directoryViewModel: RightHolderDirectoryViewModel

    @State private var isShowingPartyPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Right-Holders")
                    .font(Theme.Typography.font(.medium, size: 15))
                    .foregroundStyle(Theme.Surface.primary.foreground)
                Spacer()
                Button("+ Add Right-Holder") { isShowingPartyPicker = true }
                    .buttonStyle(SharpButtonStyle(emphasis: .secondary, surface: .primary))
            }

            if !rightHolders.isEmpty {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(Array(rightHolders.enumerated()), id: \.offset) { index, rightHolder in
                        CueRightHolderRow(
                            rightHolderIndex: index,
                            rightHolder: rightHolder,
                            isArrangementOfProtectedOriginal: isArrangementOfProtectedOriginal,
                            rightHolders: $rightHolders,
                            directoryViewModel: directoryViewModel
                        )
                        Divider().overlay(Theme.Surface.primary.foreground.opacity(0.2))
                    }
                }
            } else {
                Text("No right-holders added yet.")
                    .font(Theme.Typography.font(.regular, size: 13))
                    .foregroundStyle(Theme.Colors.ghostTextPrimary)
            }
        }
        .sheet(isPresented: $isShowingPartyPicker) {
            PartyPickerView(
                directoryViewModel: directoryViewModel,
                onSelect: { party in
                    isShowingPartyPicker = false
                    rightHolders.append(
                        CueRightHolder(
                            party: party,
                            role: .composer,
                            performanceBroadcastShare: 0,
                            mechanicalRightsShare: 0
                        )
                    )
                },
                onCancel: { isShowingPartyPicker = false }
            )
        }
    }
}

/// One `CueRightHolder` row: party display + change/remove, role picker,
/// both share fields, and the two conditional attachment prompts (SPEC.md
/// §4.4/§4.6): `publishingContractAttached` iff `role == .publisher`,
/// `arrangementAuthorizationAttached` iff `role == .arranger` *and* the
/// parent `Cue.isArrangementOfProtectedOriginal`.
private struct CueRightHolderRow: View {
    let rightHolderIndex: Int
    let rightHolder: CueRightHolder
    let isArrangementOfProtectedOriginal: Bool
    @Binding var rightHolders: [CueRightHolder]
    let directoryViewModel: RightHolderDirectoryViewModel

    @State private var isShowingPartyPicker = false

    private var resolvedName: String {
        PartyResolver.resolve(rightHolder.party, people: directoryViewModel.people, labels: directoryViewModel.labels)?
            .displayName ?? "Unknown"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Button {
                    isShowingPartyPicker = true
                } label: {
                    Text(resolvedName)
                        .font(Theme.Typography.font(.medium, size: 13))
                        .foregroundStyle(Theme.Surface.primary.foreground)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()

                Picker("", selection: roleBinding) {
                    ForEach(CueRightHolderRole.selectableInEditor, id: \.self) { role in
                        Text(role.displayName).tag(role)
                    }
                }
                .labelsHidden()
                .frame(width: 160)

                Spacer()

                Button {
                    guard rightHolders.indices.contains(rightHolderIndex) else { return }
                    rightHolders.remove(at: rightHolderIndex)
                } label: {
                    Text("✕").foregroundStyle(Theme.Surface.primary.foreground.opacity(0.6))
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }

            HStack(spacing: Theme.Spacing.sm) {
                GhostDecimalField(
                    placeholder: "Broadcast %",
                    value: performanceBroadcastShareBinding
                )
                GhostDecimalField(
                    placeholder: "Mechanical %",
                    value: mechanicalRightsShareBinding
                )
            }

            if rightHolder.role == .publisher {
                Toggle("Publishing contract attached", isOn: publishingContractAttachedBinding)
                    .toggleStyle(SharpCheckboxToggleStyle(surface: .primary))
            }
            if rightHolder.role == .arranger, isArrangementOfProtectedOriginal {
                Toggle("Arrangement authorization attached", isOn: arrangementAuthorizationAttachedBinding)
                    .toggleStyle(SharpCheckboxToggleStyle(surface: .primary))
            }
        }
        .sheet(isPresented: $isShowingPartyPicker) {
            PartyPickerView(
                directoryViewModel: directoryViewModel,
                onSelect: { party in
                    isShowingPartyPicker = false
                    replace { CueRightHolderEditing.replacing($0, party: party) }
                },
                onCancel: { isShowingPartyPicker = false }
            )
        }
    }

    /// Every field binding below funnels through here — one place that
    /// guards the index is still valid (a concurrent remove elsewhere in the
    /// same edit session) and writes the transformed row back into the
    /// shared array.
    private func replace(_ transform: (CueRightHolder) -> CueRightHolder) {
        guard rightHolders.indices.contains(rightHolderIndex) else { return }
        rightHolders[rightHolderIndex] = transform(rightHolders[rightHolderIndex])
    }

    private var roleBinding: Binding<CueRightHolderRole> {
        Binding(
            get: { rightHolder.role },
            set: { newValue in replace { CueRightHolderEditing.replacing($0, role: newValue) } }
        )
    }

    private var performanceBroadcastShareBinding: Binding<Decimal?> {
        Binding(
            get: { rightHolder.performanceBroadcastShare },
            set: { newValue in
                guard let newValue else { return }
                replace { CueRightHolderEditing.replacing($0, performanceBroadcastShare: newValue) }
            }
        )
    }

    private var mechanicalRightsShareBinding: Binding<Decimal?> {
        Binding(
            get: { rightHolder.mechanicalRightsShare },
            set: { newValue in
                guard let newValue else { return }
                replace { CueRightHolderEditing.replacing($0, mechanicalRightsShare: newValue) }
            }
        )
    }

    private var publishingContractAttachedBinding: Binding<Bool> {
        Binding(
            get: { rightHolder.publishingContractAttached },
            set: { newValue in replace { CueRightHolderEditing.replacing($0, publishingContractAttached: newValue) } }
        )
    }

    private var arrangementAuthorizationAttachedBinding: Binding<Bool> {
        Binding(
            get: { rightHolder.arrangementAuthorizationAttached },
            set: { newValue in
                replace { CueRightHolderEditing.replacing($0, arrangementAuthorizationAttached: newValue) }
            }
        )
    }
}

/// A plain, pure field-replacement helper over `CueRightHolder` — no longer
/// needs to be `@Sendable`-closure-callable from inside a `Task` (the
/// original reason it was pulled out of the ViewModel as a non-actor-isolated
/// namespace); kept as a free function purely because it's still a clean way
/// to express "replace just these fields, keep the rest" without a bespoke
/// `mutating` method on `CueRightHolder` itself.
enum CueRightHolderEditing {
    static func replacing(
        _ rightHolder: CueRightHolder,
        party: Party? = nil,
        role: CueRightHolderRole? = nil,
        performanceBroadcastShare: Decimal? = nil,
        mechanicalRightsShare: Decimal? = nil,
        publishingContractAttached: Bool? = nil,
        arrangementAuthorizationAttached: Bool? = nil
    ) -> CueRightHolder {
        CueRightHolder(
            party: party ?? rightHolder.party,
            role: role ?? rightHolder.role,
            performanceBroadcastShare: performanceBroadcastShare ?? rightHolder.performanceBroadcastShare,
            mechanicalRightsShare: mechanicalRightsShare ?? rightHolder.mechanicalRightsShare,
            publishingContractAttached: publishingContractAttached ?? rightHolder.publishingContractAttached,
            arrangementAuthorizationAttached: arrangementAuthorizationAttached
                ?? rightHolder.arrangementAuthorizationAttached
        )
    }
}

/// SUISA's C/A/AR/E legend (SPEC.md §4.4) plus the app-only `.performer` case
/// — same `static let displayNames` map + fallback-`preconditionFailure`
/// pattern `ProductionTypePicker.displayName`/`AttachmentTypePicker.displayName`
/// already establish for every other raw-value-mapped enum in this codebase.
extension CueRightHolderRole {
    private static let displayNames: [CueRightHolderRole: String] = [
        .composer: "Composer (C)",
        .author: "Author (A)",
        .arranger: "Arranger (AR)",
        .publisher: "Publisher (E)",
        .performer: "Performer",
    ]

    var displayName: String {
        guard let name = Self.displayNames[self] else {
            preconditionFailure("CueRightHolderRole.displayNames is missing a case: \(self)")
        }
        return name
    }

    /// **UI-only filter, `ROADMAP.md` D10 — `.author`/`.performer` hidden
    /// from the role picker, not removed from `CueRightHolderRole` itself
    /// (no schema change).** Neither role ever gets automatic default
    /// assignment (`CueAutoPopulation` only ever creates `.composer`/
    /// `.arranger` rows) — `.publisher` stays selectable and unaffected
    /// (it's already fully manual, same as before this change).
    static let selectableInEditor: [CueRightHolderRole] = [.composer, .arranger, .publisher]
}
