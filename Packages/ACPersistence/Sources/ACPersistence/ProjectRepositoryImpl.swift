import ACCore
import Foundation
import SwiftData

/// `ACCore.ProjectRepository`'s SwiftData-backed implementation
/// (`ROADMAP.md` D4).
///
/// ## Concurrency design
///
/// `ModelContext` is not `Sendable` and is not safe to share across
/// concurrent tasks, and `ModelContext`'s fetch/save calls are synchronous —
/// not `async` — despite being wrapped here in `async` methods. That
/// combination means a naive `actor`-only implementation would not actually
/// deliver "different `Project.ID` writes don't block each other"
/// (`ROADMAP.md` D4/T4.2, `CLAUDE.md`'s "Document & Window Model"): actor
/// isolation alone only lets other calls interleave at genuine suspension
/// points, and a synchronous `save()` call has none.
///
/// The fix: every mutating call's actual SwiftData work is dispatched into
/// its own unstructured `Task`, each opening a fresh `ModelContext` against
/// the shared, `Sendable` `ModelContainer` — never sharing a context across
/// tasks. Per-`Project.ID` write ordering is preserved by chaining each new
/// `Task` onto that ID's previous pending `Task` (`writeTails`); a write for
/// a *different* ID has no such dependency and proceeds immediately, so the
/// actor's mailbox stays free to dispatch it while another ID's write is
/// still running on its own `Task`.
///
/// **Invariant, load-bearing:** the read of `writeTails[id]`, the
/// construction of the new chained `Task`, and the write back into
/// `writeTails[id]` must happen with no `await` in between. Building a
/// `Task { ... }` value is itself synchronous — it schedules the task body
/// and returns immediately, it does not await it — so this sequence is one
/// uninterrupted span of actor-isolated execution as written below. If this
/// ever grows an `await` between the read and the write, two concurrent
/// calls for the same `Project.ID` could both read the same stale "previous
/// tail" and the same-ID serialization guarantee silently breaks. Don't
/// "simplify" this by hoisting anything above the `await task.value` at the
/// end without re-checking this invariant.
///
/// `writeTails` is never pruned — it grows by one entry per distinct
/// `Project.ID` ever created/updated/deleted during the process's lifetime
/// (same-ID calls overwrite their own entry, they don't accumulate).
/// Deliberate, not an oversight: this is a single-user desktop app's project
/// library, and a retained completed `Task<Void, Error>` is cheap even at a
/// library of hundreds of projects touched in one session. Opportunistic
/// pruning (drop entries whose task has already completed) is a real, cheap
/// option later if this ever stops being true — not needed now.
public actor ProjectRepositoryImpl: ProjectRepository {
    /// Every `SwiftDataModels` entity type — the schema `DependencyContainer`
    /// (`ROADMAP.md` D6/T6.1) constructs the real, on-disk `ModelContainer`
    /// from. Deciding the real store's on-disk location/App Sandbox container
    /// path is deliberately out of scope for this Deliverable — no App
    /// target/entitlements exist yet (`ROADMAP.md` D6, D15) — so this type
    /// only ever receives an already-constructed `ModelContainer`.
    public static let schema = Schema([
        ProjectEntity.self,
        SetupEntity.self,
        CueEntity.self,
        CueRightHolderEntity.self,
        PersonEntity.self,
        LabelEntity.self,
        AudioAssetEntity.self,
        EmbeddedMarkerEntity.self,
        BroadcastWaveMetadataEntity.self,
        WaveformPeaksEntity.self,
    ])

    private let modelContainer: ModelContainer
    private var writeTails: [Project.ID: Task<Void, Error>] = [:]
    private var subscribers: [UUID: AsyncStream<[Project]>.Continuation] = [:]

    /// Testing-only synchronization seam: if set, awaited (with the
    /// `Project.ID` being written) at the start of every write's dispatched
    /// `Task`, before it touches SwiftData — lets `ACPersistenceTests`
    /// deterministically prove same-ID writes serialize and different-ID
    /// writes don't block each other, rather than relying on wall-clock
    /// timing assumptions. Never set outside `@testable import` test code;
    /// stays `nil` (a no-op `await`) in every real code path. Set only via
    /// `setWriteHook(_:)`, not direct assignment — see that method's comment.
    private var writeHook: (@Sendable (Project.ID) async -> Void)?

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    /// Test-only. Actor-isolated `var` assignment from outside the actor
    /// needs `await` either way; a dedicated method reads more clearly at
    /// call sites than `await repository.writeHook = ...` and keeps the
    /// property itself `private`.
    func setWriteHook(_ hook: (@Sendable (Project.ID) async -> Void)?) {
        writeHook = hook
    }

    public func fetchAll() async throws -> [Project] {
        try Self.fetchAllProjects(in: modelContainer)
    }

    public func fetch(id: Project.ID) async throws -> Project? {
        try Self.fetchProject(id: id, in: modelContainer)
    }

    public func create(_ project: Project) async throws {
        try await write(project)
    }

    public func update(_ project: Project) async throws {
        try await write(project)
    }

    public func delete(id: Project.ID) async throws {
        try await enqueueWrite(for: id) { [modelContainer, writeHook] in
            await writeHook?(id)
            try Self.deleteProject(id: id, in: modelContainer)
        }
        publishSnapshot()
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

    // MARK: - Writes

    private func write(_ project: Project) async throws {
        try await enqueueWrite(for: project.id) { [modelContainer, writeHook] in
            await writeHook?(project.id)
            try Self.upsertProject(project, in: modelContainer)
        }
        publishSnapshot()
    }

    /// See the type's doc comment — the critical section below (reading
    /// `writeTails[id]`, building `task`, writing `writeTails[id]` back) is
    /// deliberately free of any `await`, which is what makes same-ID writes
    /// serialize while different-ID writes don't block each other.
    private func enqueueWrite(for id: Project.ID, work: @escaping @Sendable () async throws -> Void) async throws {
        let previousTail = writeTails[id]
        let task = Task<Void, Error> {
            // `try?`, not `try`: a failed previous write must not poison
            // every write after it. Each write is a full upsert of a
            // complete `Project` value, never a delta on top of the previous
            // write's result, so this write only needs the previous one to
            // have *finished* (so they don't race on the same
            // `ModelContext`), not to have *succeeded*. Without `try?`, one
            // transient failure would make every subsequent chained `Task`
            // for this ID rethrow before ever reaching its own `work()`,
            // permanently blocking persistence for that `Project` until
            // process relaunch. The failure itself still surfaces normally —
            // to *its own* caller, via `task.value` below — this only stops
            // it from also sabotaging writes that have nothing to do with it.
            _ = try? await previousTail?.value
            try await work()
        }
        writeTails[id] = task
        // --- end of critical section; the await below may suspend freely ---
        try await task.value
    }

    // MARK: - Subscribers

    private func register(_ continuation: AsyncStream<[Project]>.Continuation, as subscriberID: UUID) {
        subscribers[subscriberID] = continuation
        if let snapshot = try? Self.fetchAllProjects(in: modelContainer) {
            continuation.yield(snapshot)
        }
    }

    private func unregister(_ subscriberID: UUID) {
        subscribers.removeValue(forKey: subscriberID)
    }

    private func publishSnapshot() {
        guard let snapshot = try? Self.fetchAllProjects(in: modelContainer) else { return }
        for continuation in subscribers.values {
            continuation.yield(snapshot)
        }
    }

    // MARK: - SwiftData work (static: no actor isolation, safe to run inside a dispatched `Task`)

    private static func fetchAllProjects(in container: ModelContainer) throws -> [Project] {
        let context = ModelContext(container)
        let entities = try context.fetch(FetchDescriptor<ProjectEntity>())
        return try entities.map(ProjectMapper.toDomain)
    }

    private static func fetchProject(id: Project.ID, in container: ModelContainer) throws -> Project? {
        let context = ModelContext(container)
        guard let entity = try fetchEntity(id: id, in: context) else { return nil }
        return try ProjectMapper.toDomain(entity)
    }

    /// Upsert: if `project.id` already has a persisted entity, its scalar
    /// fields are updated and every child relationship is replaced wholesale
    /// (existing children deleted, fresh ones inserted from `project`'s
    /// current state) rather than diffed field-by-field. This mirrors
    /// `InMemoryProjectRepository`'s fake, where `create`/`update` are the
    /// same operation — the protocol draws no real distinction between them
    /// — and avoids the real complexity of matching old vs. new child rows
    /// for a cue-sheet-sized collection where that cost is not justified.
    private static func upsertProject(_ project: Project, in container: ModelContainer) throws {
        let context = ModelContext(container)
        if let existing = try fetchEntity(id: project.id, in: context) {
            context.delete(existing)
        }
        context.insert(ProjectMapper.toEntity(project))
        try context.save()
    }

    private static func deleteProject(id: Project.ID, in container: ModelContainer) throws {
        let context = ModelContext(container)
        guard let existing = try fetchEntity(id: id, in: context) else { return }
        context.delete(existing)
        try context.save()
    }

    private static func fetchEntity(id: Project.ID, in context: ModelContext) throws -> ProjectEntity? {
        var descriptor = FetchDescriptor<ProjectEntity>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
