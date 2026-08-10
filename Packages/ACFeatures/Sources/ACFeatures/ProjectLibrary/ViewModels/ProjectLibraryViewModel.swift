import ACCore
import Foundation

/// Backs `ProjectLibraryView` (`ROADMAP.md` D6/T6.2). Calls Use Cases only,
/// never a Repository directly, per `CONTRIBUTING.md` §6.
@Observable
@MainActor
public final class ProjectLibraryViewModel {
    public private(set) var projects: [Project] = []
    public var errorMessage: String?

    private let observeProjectsUseCase: ObserveProjectsUseCase
    private let createProjectUseCase: CreateProjectUseCase
    private let deleteProjectUseCase: DeleteProjectUseCase
    /// `@ObservationIgnored` + `nonisolated(unsafe)`: `deinit` is never
    /// actor-isolated, even on a `@MainActor` class, so cancelling this from
    /// `deinit` needs to reach it without hopping onto the actor.
    /// `@ObservationIgnored` keeps this a plain stored property rather than
    /// one the `@Observable` macro rewrites into a tracked computed property
    /// (which is what made a bare `nonisolated` ambiguous here) — this
    /// property is implementation detail no View ever reads, so it never
    /// needed observation tracking anyway. Safe because `Task.cancel()` is
    /// itself thread-safe, and nothing else ever mutates this property from
    /// off the main actor.
    @ObservationIgnored
    private nonisolated(unsafe) var observationTask: Task<Void, Never>?

    public init(
        observeProjectsUseCase: ObserveProjectsUseCase,
        createProjectUseCase: CreateProjectUseCase,
        deleteProjectUseCase: DeleteProjectUseCase
    ) {
        self.observeProjectsUseCase = observeProjectsUseCase
        self.createProjectUseCase = createProjectUseCase
        self.deleteProjectUseCase = deleteProjectUseCase
    }

    deinit {
        observationTask?.cancel()
    }

    /// Subscribes to the live `Project` list (`CLAUDE.md`, "Single Source of
    /// Truth") — idempotent, so a View's `.task { }` can call this on every
    /// appearance without starting a second subscription. Called once per
    /// window per app launch in practice, but safe either way.
    public func startObserving() {
        guard observationTask == nil else { return }
        let stream = observeProjectsUseCase.observeAll()
        observationTask = Task { [weak self] in
            for await snapshot in stream {
                self?.projects = snapshot
            }
        }
    }

    public func createProject(name: String) async {
        do {
            try await createProjectUseCase.create(name: name)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func deleteProject(id: Project.ID) async {
        do {
            try await deleteProjectUseCase.delete(id: id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
