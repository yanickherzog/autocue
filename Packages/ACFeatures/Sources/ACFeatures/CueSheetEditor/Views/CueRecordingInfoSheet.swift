import ACCore
import ACDesignSystem
import SwiftUI

/// One cue's Label sheet — `Cue.recordingLabel`/`.recordingLabelNumber`/
/// `.recordingISRC` (SPEC.md §4.3), a licensed/pre-existing recording's own
/// identity, as distinct from this work's right-holder split. Reached via
/// `CueTableView`'s "Label" column, a dedicated icon separate from "Royalty
/// Split"'s — this sheet never shares state or presentation with
/// `CueRowDetailView`, since the two edit genuinely unrelated data.
///
/// **User-facing name is "Label," not "Recording Info"** — renamed from
/// this sheet/column's original name after real manual testing; the type's
/// own name (`CueRecordingInfoSheet`) and the `+RecordingInfo.swift`
/// ViewModel extension it talks to are unchanged, since internal names
/// don't need to track every UI copy change (`docs/DECISIONS.md`).
///
/// **All three fields write through immediately/debounced, not as a single
/// local buffer committed on "Done" — unlike `CueRowDetailView`'s right-holder
/// buffer.** There is no equivalent "does this still sum to 100%" live-edit
/// hazard here (SPEC.md §4.18's debouncing rule, not the narrower
/// buffer-until-"Done" exception `CueRowDetailView` itself documents as
/// scoped to its own one case) — the Label picker selection writes at once
/// (a discrete action), and the two text fields debounce the same way every
/// other field edit in this app already does.
struct CueRecordingInfoSheet: View {
    let cueIndex: Int
    @Bindable var viewModel: CueDetectionReviewViewModel
    let directoryViewModel: RightHolderDirectoryViewModel
    let undoManager: UndoManager?
    let onDismiss: () -> Void

    @State private var isShowingLabelPicker = false
    @State private var labelNumberText: String
    @State private var isrcText: String

    init(
        cueIndex: Int,
        viewModel: CueDetectionReviewViewModel,
        directoryViewModel: RightHolderDirectoryViewModel,
        undoManager: UndoManager?,
        onDismiss: @escaping () -> Void
    ) {
        self.cueIndex = cueIndex
        self.viewModel = viewModel
        self.directoryViewModel = directoryViewModel
        self.undoManager = undoManager
        self.onDismiss = onDismiss
        let existing = viewModel.cues.indices.contains(cueIndex) ? viewModel.cues[cueIndex] : nil
        _labelNumberText = State(initialValue: existing?.recordingLabelNumber ?? "")
        _isrcText = State(initialValue: existing?.recordingISRC ?? "")
    }

    private var cue: Cue? {
        viewModel.cues.indices.contains(cueIndex) ? viewModel.cues[cueIndex] : nil
    }

    private var resolvedLabelName: String? {
        guard let party = cue?.recordingLabel else { return nil }
        return PartyResolver.resolve(party, people: directoryViewModel.people, labels: directoryViewModel.labels)?
            .displayName
    }

    /// Non-blocking — the same "flag a likely typo, never block on it"
    /// lesson a real fabricated-IPI-number bug already established for
    /// `IPINumber` elsewhere in this app (`docs/DECISIONS.md`).
    private var isISRCShapeQuestionable: Bool {
        let trimmed = isrcText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !ISRCNumber.isValid(trimmed)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if let cue {
                    Text("Label")
                        .font(Theme.Typography.font(.medium, size: 17))
                        .foregroundStyle(Theme.Surface.primary.foreground)
                    Text(cue.title.isEmpty ? "Untitled Cue" : cue.title)
                        .font(Theme.Typography.font(.regular, size: 13))
                        .foregroundStyle(Theme.Colors.ghostTextPrimary)

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        HStack {
                            Text(resolvedLabelName ?? "No label selected")
                                .font(Theme.Typography.font(.regular, size: 13))
                                .foregroundStyle(
                                    resolvedLabelName == nil
                                        ? Theme.Colors.ghostTextPrimary
                                        : Theme.Surface.primary.foreground
                                )
                            Spacer()
                            if resolvedLabelName != nil {
                                Button("Clear") {
                                    Task { await viewModel.recordingLabelCleared(cueID: cue.id) }
                                }
                                .buttonStyle(SharpButtonStyle(emphasis: .secondary, surface: .primary))
                            }
                            Button(resolvedLabelName == nil ? "Select…" : "Change…") {
                                isShowingLabelPicker = true
                            }
                            .buttonStyle(SharpButtonStyle(emphasis: .secondary, surface: .primary))
                        }
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Label-Nr.")
                            .font(Theme.Typography.font(.medium, size: 13))
                            .foregroundStyle(Theme.Surface.primary.foreground)
                        GhostTextField(placeholder: "Catalog number", text: $labelNumberText)
                            .onChange(of: labelNumberText) { _, newValue in
                                viewModel.recordingLabelNumberChanged(cueID: cue.id, newValue: newValue)
                            }
                    }

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("ISRC-Nr.")
                            .font(Theme.Typography.font(.medium, size: 13))
                            .foregroundStyle(Theme.Surface.primary.foreground)
                        GhostTextField(placeholder: "CC-XXX-YY-NNNNN", text: $isrcText)
                            .onChange(of: isrcText) { _, newValue in
                                viewModel.recordingISRCChanged(cueID: cue.id, newValue: newValue)
                            }
                        if isISRCShapeQuestionable {
                            Text("Doesn't look like a valid ISRC (CC-XXX-YY-NNNNN) — saved as typed.")
                                .font(Theme.Typography.font(.regular, size: 11))
                                .foregroundStyle(Theme.Colors.accent)
                        }
                    }
                } else {
                    Text("This cue no longer exists.")
                        .font(Theme.Typography.font(.regular, size: 13))
                        .foregroundStyle(Theme.Colors.ghostTextPrimary)
                }

                HStack {
                    Spacer()
                    Button("Copy Label to other Cues", action: copyLabelToOtherCues)
                        .buttonStyle(SharpButtonStyle(emphasis: .secondary, surface: .primary))
                    Button("Done", action: onDismiss)
                        .buttonStyle(SharpButtonStyle(emphasis: .primary, surface: .primary))
                }
            }
            .padding(Theme.Spacing.lg)
        }
        .frame(width: 420, height: 420)
        .background(Theme.Surface.primary.background)
        .fixedAppearance(for: .primary)
        .sheet(isPresented: $isShowingLabelPicker) {
            PartyPickerView(
                directoryViewModel: directoryViewModel,
                scope: .labelOnly,
                onSelect: { party in
                    isShowingLabelPicker = false
                    guard let cue else { return }
                    Task { await viewModel.recordingLabelSelected(cueID: cue.id, party: party) }
                },
                onCancel: { isShowingLabelPicker = false }
            )
        }
    }

    /// Copies this cue's current Label/Label-Nr. onto every other cue in
    /// the project — never the ISRC-Nr., which identifies one specific
    /// master recording and must stay per-cue (SPEC.md §4.26). Uses the
    /// cue's own already-saved `recordingLabel`/`.recordingLabelNumber`
    /// (both write through immediately/debounced as the user edits them, so
    /// `cue` already reflects the sheet's current values — unlike
    /// `CueRowDetailView`'s right-holder buffer, there is no separate
    /// not-yet-committed local state to read here).
    private func copyLabelToOtherCues() {
        guard let cue else { return }
        viewModel.copyRecordingLabelToOtherCuesRequested(
            recordingLabel: cue.recordingLabel,
            recordingLabelNumber: cue.recordingLabelNumber,
            undoManager: undoManager
        )
    }
}
