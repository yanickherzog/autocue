import ACCore
import Foundation

/// An in-memory `ProjectRepository` fake for ViewModel/Use Case tests
/// (`ROADMAP.md` D3/T3.4) — never `AVFoundation`/`SwiftData`, per
/// `CONTRIBUTING.md` §5's "ViewModels: test against the fakes in
/// `ACTestSupport`, never against real `AVFoundation`/`SwiftData`."
///
/// An `actor`, not a lock-guarded class: every protocol method is already
/// `async`, and actor isolation is the standard Swift Concurrency way to make
/// the backing dictionary safe under concurrent access without hand-rolled
/// locking. `observeAll()` is the one `nonisolated`, non-`async` requirement
/// (matching `ProjectRepository`'s signature); it registers its continuation
/// back on the actor via a detached `Task`, so it stays safe to call from any
/// context while still hopping onto actor isolation to touch shared state.
///
/// Supports multiple concurrent `observeAll()` subscribers, each independently
/// receiving every subsequent mutation's fresh snapshot — this is what lets
/// `ROADMAP.md` D11's cross-ViewModel propagation test construct two
/// ViewModels against the same fake instance and observe both updating.
public actor InMemoryProjectRepository: ProjectRepository {
    private var projects: [Project.ID: Project]
    private var subscribers: [UUID: AsyncStream<[Project]>.Continuation] = [:]

    public init(projects: [Project] = []) {
        self.projects = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
    }

    public func fetchAll() async throws -> [Project] {
        Array(projects.values)
    }

    public func fetch(id: Project.ID) async throws -> Project? {
        projects[id]
    }

    public func create(_ project: Project) async throws {
        projects[project.id] = project
        publish()
    }

    public func update(_ project: Project) async throws {
        projects[project.id] = project
        publish()
    }

    /// No `await` between reading `projects[id]` and writing it back, so
    /// this is atomic under actor isolation the same way
    /// `ProjectRepositoryImpl`'s real implementation is via its
    /// `writeTails` queue — see `ProjectRepository`'s doc comment for why
    /// that matters.
    @discardableResult
    public func update(
        id: Project.ID,
        transform: @escaping @Sendable (Project) throws -> Project
    ) async throws -> Project? {
        guard let current = projects[id] else { return nil }
        let updated = try transform(current)
        projects[id] = updated
        publish()
        return updated
    }

    public func delete(id: Project.ID) async throws {
        projects.removeValue(forKey: id)
        publish()
    }

    public nonisolated func observeAll() -> AsyncStream<[Project]> {
        AsyncStream { continuation in
            let subscriberID = UUID()
            Task { await self.register(continuation, as: subscriberID) }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                Task { await self.unregister(subscriberID) }
            }
        }
    }

    private func register(_ continuation: AsyncStream<[Project]>.Continuation, as subscriberID: UUID) {
        subscribers[subscriberID] = continuation
        continuation.yield(Array(projects.values))
    }

    private func unregister(_ subscriberID: UUID) {
        subscribers.removeValue(forKey: subscriberID)
    }

    private func publish() {
        let snapshot = Array(projects.values)
        for continuation in subscribers.values {
            continuation.yield(snapshot)
        }
    }
}
