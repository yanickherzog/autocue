import Foundation

/// The Data-layer boundary for persisted `Project` storage — implemented by
/// `ACPersistence`'s `ProjectRepositoryImpl` (`ROADMAP.md` D4), backed by
/// `SwiftData`. `ACCore` never imports `SwiftData`; this protocol is what
/// lets Domain/Presentation depend on persisted `Project` state without
/// depending on how it's persisted (`CLAUDE.md`, "Single Source of Truth").
///
/// `Sendable` per `CLAUDE.md`, "Use Cases Are Stateless": Use Cases hold the
/// same Repository instance across concurrent calls from multiple screens,
/// so the protocol itself must be safe to call concurrently — whether a
/// given implementation is internally an actor is a Data-layer detail this
/// protocol doesn't need to know about.
///
/// `observeAll()` is the live-observation half of "Single Source of Truth":
/// every mutating method republishes the fresh result into it, so a
/// subscriber (typically via a small wrapping Use Case) sees live updates
/// with no manual refresh — this is what list-style views consume instead of
/// `@Query`.
public protocol ProjectRepository: Sendable {
    func fetchAll() async throws -> [Project]
    func fetch(id: Project.ID) async throws -> Project?
    func create(_ project: Project) async throws
    func update(_ project: Project) async throws
    func delete(id: Project.ID) async throws
    func observeAll() -> AsyncStream<[Project]>
}
