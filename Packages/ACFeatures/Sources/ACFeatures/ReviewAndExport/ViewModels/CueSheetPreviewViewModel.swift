import ACCore
import Foundation

/// Backs `CueSheetPreviewView` (`ROADMAP.md` D11/T11.2) — the on-screen
/// preview of the producer-facing cue sheet PDF, drawing the exact same
/// `CueSheetPageLayout` values `PDFCueSheetRenderer` draws into the real
/// file. Built in the same Task as the layout computation and the PDF
/// renderer, not deferred to T11.5 — per the project owner's own reasoning:
/// splitting the layout's first real consumer from its computation risks
/// the layout being validated only against the PDF renderer, with the
/// preview added later with less context on why it must never fall back to
/// native SwiftUI `Text` layout (`CLAUDE.md`, "Export Architecture").
///
/// Same live-subscription shape as `ReviewViewModel` (`ROADMAP.md` D11/T11.1)
/// — subscribes to `ObserveProjectsUseCase.observeAll()` indefinitely (never
/// breaks after the first snapshot, since this screen owns no working copy
/// to protect), recomputing the layout via `ComputeCueSheetLayoutUseCase` on
/// every emission so the preview never needs an explicit refresh.
@Observable
@MainActor
public final class CueSheetPreviewViewModel {
    public let projectID: Project.ID
    public private(set) var pages: [CueSheetPageLayout] = []
    public private(set) var projectNotFound = false

    private let observeProjectsUseCase: ObserveProjectsUseCase
    private let computeCueSheetLayoutUseCase: ComputeCueSheetLayoutUseCase

    public init(
        projectID: Project.ID,
        observeProjectsUseCase: ObserveProjectsUseCase,
        computeCueSheetLayoutUseCase: ComputeCueSheetLayoutUseCase
    ) {
        self.projectID = projectID
        self.observeProjectsUseCase = observeProjectsUseCase
        self.computeCueSheetLayoutUseCase = computeCueSheetLayoutUseCase
    }

    public func load() async {
        for await projects in observeProjectsUseCase.observeAll() {
            guard let project = projects.first(where: { $0.id == projectID }) else {
                projectNotFound = true
                break
            }
            projectNotFound = false
            pages = computeCueSheetLayoutUseCase.compute(for: project)
        }
    }
}
