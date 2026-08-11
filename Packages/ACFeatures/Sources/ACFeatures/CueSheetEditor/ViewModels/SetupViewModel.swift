import ACCore
import Foundation

/// Backs `SetupView` (`ROADMAP.md` D7/T7.1–T7.2). Calls Use Cases only, never
/// a Repository directly, per `CONTRIBUTING.md` §6.
///
/// **Owns the `setup` slice; treats `people`/`labels` as read-only display
/// context.** This window is the sole editor of this `Project`'s `Setup`
/// (`OpenProjectWindowRegistry`, `CLAUDE.md` "Document & Window Model"), so
/// once the real value has been fetched (see `load()` below), it's never
/// overwritten by a background refresh — a live subscription that could
/// apply an incoming snapshot mid-edit would risk clobbering an in-progress,
/// not-yet-saved keystroke. `people`/`labels` are different:
/// `RightHolderDirectoryViewModel` (`ROADMAP.md` D7/T7.3) can change them
/// from the same window (creating a `Person`/`Label` inline via the party
/// picker), and `SetupViewModel` needs the fresh directory to resolve
/// `producer`/`directorOrPrincipal`/`declarant` display names via
/// `PartyResolver` — every `load()` call refreshes them, not just the first.
///
/// **No `initialSetup` parameter — `load()` fetches it asynchronously.**
/// `DependencyContainer`'s factory methods are called synchronously from
/// `NavigationSplitView`'s `detail:` closure (`CLAUDE.md`, "Dependency
/// Injection Pattern"), with no way to `await` a repository fetch first —
/// this Use Case in particular has no "one-shot fetch by id" beyond
/// `ObserveProjectsUseCase.observeAll()`'s stream, so a real fetch is
/// unavoidably `async`. `setup` therefore starts as a placeholder empty
/// value (the same shape `CreateProjectUseCase.makeDefaultSetup` produces
/// for a brand-new `Project`) until `SetupView`'s `.task` calls `load()` —
/// the same "start empty, populate live" pattern `ProjectLibraryViewModel`
/// already establishes for its own `projects` list.
///
/// **Save timing — debounced vs. immediate, split the same way `SPEC.md`
/// §4.18 splits Cue mutations:** `updateDebounced` is for continuous
/// field-level edits (typing a title) where debouncing avoids a
/// save-per-keystroke storm. `updateImmediately` is for discrete, complete
/// actions — picking a `Party`, toggling a `ProductionType`/`AttachmentType`/
/// `ExploitationType` checkbox — which have nothing further to type, so
/// debouncing would only delay an already-final save.
@Observable
@MainActor
public final class SetupViewModel {
    public let projectID: Project.ID
    public private(set) var setup: Setup
    public private(set) var people: [Person] = []
    public private(set) var labels: [Label] = []
    public var errorMessage: String?
    /// Set once `load()` has confirmed, from a real repository snapshot,
    /// that no `Project` with `projectID` exists — the defensive fallback
    /// `ProjectWindowView` gates its entire `detail` area on (`ROADMAP.md`
    /// D7). Second layer of protection alongside the `.id(projectID)` fix on
    /// `AutoCueApp`'s `WindowGroup(for:)`: even if a window is ever bound to
    /// a stale/nonexistent `Project.ID` for a reason not yet found, this
    /// turns that into a clear, dedicated screen state instead of a silent
    /// infinite load plus repeated `ProjectNotFoundError` alerts on every
    /// save attempt. See `docs/DECISIONS.md`.
    public private(set) var projectNotFound = false

    /// Forwards `Setup.missingRequiredFields` verbatim — no filtering.
    ///
    /// **`.productionRuntime` was excluded here for a while, during the
    /// period this screen had no input for it** (moved to Review & Export,
    /// D11, not built yet) — surfacing it in the gated-navigation check
    /// (`ProjectWindowView.sidebarButton`, `ROADMAP.md` D7) would have been a
    /// permanently-unsatisfiable block with no way to act on it from here.
    /// Reversed once `productionRuntime` ("Production Runtime") was
    /// re-added to this screen — the exclusion's own premise no longer
    /// holds, since there's now a real way to fix it from here. See
    /// `docs/DECISIONS.md`.
    public var missingRequiredFields: [SetupRequiredField] {
        setup.missingRequiredFields
    }

    private let observeProjectsUseCase: ObserveProjectsUseCase
    private let updateSetupUseCase: UpdateSetupUseCase
    private let debounceNanoseconds: UInt64

    /// See `ProjectLibraryViewModel`'s identical property for why this needs
    /// `@ObservationIgnored` + `nonisolated(unsafe)`: `deinit` is never
    /// actor-isolated, even on a `@MainActor` class.
    @ObservationIgnored
    private nonisolated(unsafe) var saveTask: Task<Void, Never>?

    @ObservationIgnored
    private var hasLoadedInitialSetup = false

    public init(
        projectID: Project.ID,
        observeProjectsUseCase: ObserveProjectsUseCase,
        updateSetupUseCase: UpdateSetupUseCase,
        debounceNanoseconds: UInt64 = 500_000_000
    ) {
        self.projectID = projectID
        setup = Setup(
            title: "",
            productionRuntime: .zero,
            totalMusicRuntime: .zero,
            productionYear: 0,
            containsAdditionalUndeclaredWorks: .notKnown,
            productionTypes: [],
            declarationDate: Date()
        )
        self.observeProjectsUseCase = observeProjectsUseCase
        self.updateSetupUseCase = updateSetupUseCase
        self.debounceNanoseconds = debounceNanoseconds
    }

    deinit {
        saveTask?.cancel()
    }

    /// One-shot fetch/refresh from the live stream's next emission. Always
    /// refreshes `people`/`labels`; populates `setup` from the real
    /// persisted value **only the first time** — safe to call repeatedly
    /// (e.g. every time the party picker sheet is presented) without ever
    /// clobbering an in-progress edit on a subsequent call.
    ///
    /// **Settles on the very first snapshot either way — found or not —
    /// rather than looping until a match appears.** `observeAll()`'s stream
    /// yields the true current state immediately on subscribe
    /// (`ProjectRepositoryImpl.register`), so the first emission already
    /// answers "does this `Project` genuinely exist right now" with
    /// confidence; a `Project` this window is bound to isn't going to start
    /// existing later on its own. An earlier version of this method
    /// `continue`d forever on a non-match instead of ever setting
    /// `projectNotFound` — which meant a window bound to a deleted/stale
    /// `Project.ID` (`ROADMAP.md` D7) hung in a silent, permanently-loading
    /// state, with the *only* visible symptom being repeated
    /// `ProjectNotFoundError` alerts the moment the user tried to edit
    /// anything. Breaking here immediately is also what makes this method
    /// actually awaitable in a test against a `Project` that doesn't exist —
    /// the old version would have hung a test calling it forever.
    public func load() async {
        for await projects in observeProjectsUseCase.observeAll() {
            guard let project = projects.first(where: { $0.id == projectID }) else {
                projectNotFound = true
                break
            }
            projectNotFound = false
            if !hasLoadedInitialSetup {
                setup = project.setup
                hasLoadedInitialSetup = true
            }
            people = project.people
            labels = project.labels
            break
        }
    }

    public func updateDebounced(_ newSetup: Setup) {
        setup = newSetup
        saveTask?.cancel()
        saveTask = Task { [weak self, debounceNanoseconds] in
            try? await Task.sleep(nanoseconds: debounceNanoseconds)
            guard !Task.isCancelled else { return }
            await self?.save()
        }
    }

    public func updateImmediately(_ newSetup: Setup) async {
        saveTask?.cancel()
        saveTask = nil
        setup = newSetup
        await save()
    }

    /// Flushes any pending debounced save immediately — called when this
    /// screen disappears (tab switch or window close), so an edit is never
    /// silently lost mid-debounce (`CLAUDE.md`, "Document & Window Model"
    /// consequences). A no-op if nothing is pending, so it never produces a
    /// spurious save (and `Project.updatedAt` bump) on an unmodified `Setup`.
    public func flushPendingSave() async {
        guard saveTask != nil else { return }
        saveTask?.cancel()
        saveTask = nil
        await save()
    }

    private func save() async {
        do {
            try await updateSetupUseCase.update(projectID: projectID, setup: setup)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
