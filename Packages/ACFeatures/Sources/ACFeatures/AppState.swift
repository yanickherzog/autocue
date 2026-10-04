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

/// The four always-accessible section tabs a Project window's
/// `NavigationSplitView` shell shows (`CLAUDE.md`, "Navigation Model") —
/// small and tightly coupled to `AppState`, so it's co-located here rather
/// than given its own file, the same convention already used for
/// `AdditionalWorksDeclaration`/`CueSource`.
///
/// **`.waFilmForm` added at `ROADMAP.md` D12/T12.4** — a real change to
/// `CLAUDE.md`'s Navigation Model (previously "three always-visible tabs"),
/// not an incidental addition; see that section's own updated text and
/// `docs/DECISIONS.md` for why this is a fourth co-equal tab rather than a
/// section nested inside Review & Export.
public enum ProjectSection: CaseIterable, Equatable {
    case setup
    case cueSheet
    case reviewAndExport
    case waFilmForm
}
