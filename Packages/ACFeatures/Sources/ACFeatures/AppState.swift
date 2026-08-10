import Foundation

/// Per-window navigation state (`ROADMAP.md` D6/T6.1, `CLAUDE.md`'s
/// "Document & Window Model"). One instance is constructed per Project
/// window, when that window opens — never a single app-wide singleton.
/// `selectedProjectID` is deliberately absent: which `Project` a window
/// shows is the `Project.ID` its `WindowGroup(for:)` instance was opened
/// with, not a separately-tracked mutable field that could drift out of
/// sync with the window itself.
@Observable
public final class AppState {
    public var selectedSection: ProjectSection = .setup

    public init() {}
}

/// The three always-accessible section tabs a Project window's
/// `NavigationSplitView` shell shows (`CLAUDE.md`, "Navigation Model") —
/// small and tightly coupled to `AppState`, so it's co-located here rather
/// than given its own file, the same convention already used for
/// `AdditionalWorksDeclaration`/`CueSource`.
public enum ProjectSection: CaseIterable, Equatable {
    case setup
    case cueSheet
    case reviewAndExport
}
