import ACCore
import ACDesignSystem
import SwiftUI

/// One cue's detail sheet (`ROADMAP.md` D10/T10.2, SPEC.md §4.19 capability
/// 3) — reached via `CueTableView`'s detail-icon column, since the row's
/// plain click is already claimed by click-to-play (`ROADMAP.md` D9/T9.4).
///
/// **No Start Timecode field — removed at D10's second round, per direct
/// instruction ("irrelevant here and shouldn't be shown in this sheet").**
/// This sheet is now exclusively the right-holder/"Royalty Split" editor;
/// `CueDetectionReviewViewModel.startTimecodeChanged`/`saveStartTimecode`
/// (`+RowDetail.swift`) are kept, unused, the same "kept in case a future
/// revision needs them" treatment `UpdateCueUseCase.add`/`.reorder` already
/// got at the same Deliverable — see `docs/DECISIONS.md`.
///
/// **Right-holder editing is a local, freely-editable buffer, committed in
/// one write on "Done."** `localRightHolders` is seeded from the cue when
/// the sheet opens and is the only thing `CueRightHolderEditorView` reads or
/// mutates while the sheet is up — no per-keystroke round trip to
/// `ProjectRepository`, and therefore nothing that can clamp/reject a
/// keystroke based on a pool's current running total, which the sheet's
/// pre-existing live-write design used to do by accident once a pool was
/// already at or over 100%. Validation only ever runs once, at "Done," and
/// only ever produces a warning — it never blocks the commit or the sheet's
/// dismissal, consistent with `CueTableView`'s own non-blocking row
/// indicator for the same rule.
struct CueRowDetailView: View {
    let cueIndex: Int
    @Bindable var viewModel: CueDetectionReviewViewModel
    let directoryViewModel: RightHolderDirectoryViewModel
    let undoManager: UndoManager?
    let onDismiss: () -> Void

    @State private var localRightHolders: [CueRightHolder]
    @State private var isShowingValidationWarning = false
    /// Built fresh from the real `[CueRightHolderValidationIssue]` array each
    /// time "Done" finds a problem — never a fixed string. See
    /// `CueRightHolderValidationMessageFormatter`'s own doc comment for the
    /// real bug this replaces: a hardcoded "pool doesn't sum to 100%"
    /// message shown even when the actual issue was an unrelated missing
    /// attachment checkbox.
    @State private var validationWarningMessages: [String] = []

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
        _localRightHolders = State(initialValue: existing?.rightHolders ?? [])
    }

    private var cue: Cue? {
        viewModel.cues.indices.contains(cueIndex) ? viewModel.cues[cueIndex] : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if let cue {
                    Text(cue.title.isEmpty ? "Untitled Cue" : cue.title)
                        .font(Theme.Typography.font(.medium, size: 17))
                        .foregroundStyle(Theme.Surface.primary.foreground)

                    CueRightHolderEditorView(
                        rightHolders: $localRightHolders,
                        isArrangementOfProtectedOriginal: cue.isArrangementOfProtectedOriginal,
                        directoryViewModel: directoryViewModel
                    )
                } else {
                    Text("This cue no longer exists.")
                        .font(Theme.Typography.font(.regular, size: 13))
                        .foregroundStyle(Theme.Colors.ghostTextPrimary)
                }

                HStack {
                    Spacer()
                    Button("Copy Split to Other Cues", action: copySplitToOtherCues)
                        .buttonStyle(SharpButtonStyle(emphasis: .secondary, surface: .primary))
                    Button("Done", action: commitAndDismiss)
                        .buttonStyle(SharpButtonStyle(emphasis: .primary, surface: .primary))
                }
            }
            .padding(Theme.Spacing.lg)
        }
        .frame(width: 460, height: 520)
        .background(Theme.Surface.primary.background)
        .fixedAppearance(for: .primary)
        .alert("Right-Holder Shares", isPresented: $isShowingValidationWarning) {
            // Closes only this alert — it must NOT also call `onDismiss()`.
            // The data is already saved (`commitAndDismiss` commits before
            // ever showing this alert); the point of staying open is letting
            // the user actually fix the pool without having to reopen the
            // sheet and re-enter everything.
            Button("OK") {}
        } message: {
            // Every real issue gets its own line — never just the first —
            // so a second, unrelated problem isn't discovered only on a
            // later "Done" press.
            Text(
                (validationWarningMessages + [
                    "This is saved — the cue list will show a warning icon for this cue until it's corrected.",
                ]).joined(separator: "\n")
            )
        }
    }

    private func commitAndDismiss() {
        guard let cue else {
            onDismiss()
            return
        }
        let rightHolders = localRightHolders
        Task {
            await viewModel.commitRightHolderEdits(cueID: cue.id, rightHolders: rightHolders)
        }
        let candidate = Cue(
            id: cue.id,
            title: cue.title,
            workNumber: cue.workNumber,
            duration: cue.duration,
            rightHolders: rightHolders,
            isArrangementOfProtectedOriginal: cue.isArrangementOfProtectedOriginal,
            source: cue.source,
            startTimecode: cue.startTimecode,
            notes: cue.notes
        )
        let issues = ValidateCueRightHolderSharesUseCase.validate(candidate)
        if issues.isEmpty {
            onDismiss()
        } else {
            validationWarningMessages = CueRightHolderValidationMessageFormatter.messages(
                for: issues,
                rightHolders: rightHolders,
                people: directoryViewModel.people,
                labels: directoryViewModel.labels
            )
            isShowingValidationWarning = true
        }
    }

    private func copySplitToOtherCues() {
        viewModel.copySplitToOtherCuesRequested(rightHolders: localRightHolders, undoManager: undoManager)
    }
}
