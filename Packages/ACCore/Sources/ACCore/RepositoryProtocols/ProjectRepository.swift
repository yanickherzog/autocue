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
///
/// **`update(id:transform:)` vs. plain `update(_:)`:** plain `update(_:)`
/// persists exactly the `Project` value the caller already holds — correct
/// when a caller has just legitimately replaced the whole thing (e.g.
/// project creation). It is **not** safe for "fetch the current `Project`,
/// change one slice of it, persist" — two independent callers each doing
/// that for *different* slices of the *same* `Project.ID` (e.g.
/// `UpdateSetupUseCase` changing `setup` and `UpdateRightHolderDirectoryUseCase`
/// changing `people`/`labels`, both real, concurrent call paths from the same
/// Project window — `CLAUDE.md`'s "Document & Window Model") can both fetch
/// before either writes; the second write then persists a `Project` built
/// from a snapshot taken *before* the first write landed, silently
/// discarding it. `update(id:transform:)` closes that gap: the fetch and the
/// write happen as a single operation, serialized against any other write
/// for the same `id` exactly the way `create`/`update`/`delete` already are
/// — `transform` always runs against the truly-current persisted `Project`,
/// never a stale caller-held snapshot. Returns `nil` (without calling
/// `transform`) if `id` has no persisted `Project`. Prefer this over
/// fetch-then-`update(_:)` for any write that only ever needs to replace one
/// slice of a `Project` it doesn't otherwise own.
public protocol ProjectRepository: Sendable {
    func fetchAll() async throws -> [Project]
    func fetch(id: Project.ID) async throws -> Project?
    func create(_ project: Project) async throws
    func update(_ project: Project) async throws
    @discardableResult
    func update(id: Project.ID, transform: @escaping @Sendable (Project) throws -> Project) async throws -> Project?
    func delete(id: Project.ID) async throws
    func observeAll() -> AsyncStream<[Project]>
}
