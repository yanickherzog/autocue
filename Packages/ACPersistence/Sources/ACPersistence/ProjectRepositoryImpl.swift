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
///
/// ## Reader/writer barrier
///
/// `writeTails` alone only serializes writes against *other writes for the
/// same `Project.ID`*. It says nothing about `fetchAllProjects` — the
/// all-projects snapshot fetch used after every write and on new
/// subscription — which touches *every* project's entity graph, including
/// ones with no relationship to whichever write just completed. A real
/// crash was reproduced (2026-09-05, live under a debugger — see
/// `docs/DECISIONS.md`) where one project's snapshot fetch was
/// mid-fault-resolution on a *different* project's entity at the exact
/// moment that other project's own, entirely independent write deleted and
/// reinserted it — different `Project.ID`s are deliberately allowed to
/// write concurrently, so nothing prevented that overlap. See
/// `ProjectRepositoryImpl+ReaderWriterBarrier.swift` for the fix and its
/// full reasoning (split into its own file purely to keep this one under
/// this project's line-length limit — it's still the same type, just via
/// an extension).
public actor ProjectRepositoryImpl: ProjectRepository {
    /// Every `SwiftDataModels` entity type — the schema `DependencyContainer`
    /// (`ROADMAP.md` D6/T6.1) constructs the real, on-disk `ModelContainer`
    /// from. Deciding the real store's on-disk location/App Sandbox container
    /// path is deliberately out of scope for this Deliverable — no App
    /// target/entitlements exist yet (`ROADMAP.md` D6, D15) — so this type
    /// only ever receives an already-constructed `ModelContainer`.
    ///
    /// A function, not a `static let`: `Schema` is a class, and a single
    /// shared `Schema` instance reused across many `ModelContainer`s in the
    /// same process (as this test target's helper originally did, once per
    /// test) was a candidate fix for a real, repeatable SIGTRAP crash hit on
    /// PR #4's CI runner. **It turned out not to be the actual cause** (see
    /// `docs/DECISIONS.md` for the real one) — kept anyway, since building a
    /// fresh `Schema` per container is correct on its own merits regardless.
    public static func makeSchema() -> Schema {
        Schema([
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
    }

    /// Not `private`: read from `ProjectRepositoryImpl+ReaderWriterBarrier.swift`'s
    /// extension (Swift extensions can't add stored properties, so the
    /// barrier's SwiftData-work methods that need it live in a different
    /// file from this declaration) — `internal`, never exposed outside the
    /// `ACPersistence` module.
    let modelContainer: ModelContainer
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

    /// Testing-only synchronization seams for the reader/writer barrier
    /// (`ProjectRepositoryImpl+ReaderWriterBarrier.swift`): if set, awaited
    /// immediately after a write's mutation phase (or a snapshot fetch's
    /// reader phase) actually acquires its barrier slot — before any real
    /// work happens while holding it. Lets `ACPersistenceTests`
    /// deterministically pause a writer/reader *while it genuinely holds
    /// the barrier* (proving the other role actually blocks), or inject a
    /// thrown error at that exact point (proving a slot is still released
    /// on failure). Never set outside `@testable import` test code; stay
    /// `nil` (a no-op) in every real code path. Not `private` — set and
    /// fired from that extension file; see `modelContainer`'s comment for
    /// why.
    var postAcquireWriterSlotHook: (@Sendable () async throws -> Void)?
    var postAcquireReaderSlotHook: (@Sendable () async throws -> Void)?

    /// Reader/writer barrier state (`ProjectRepositoryImpl+ReaderWriterBarrier.swift`).
    /// Declared here because Swift extensions can't add stored properties;
    /// not `private` for the same cross-file reason as `modelContainer`,
    /// above.
    var activeWriterCount = 0
    var writerWaiters: [UUID: CheckedContinuation<Void, Error>] = [:]
    var activeReaderCount = 0
    var readerWaiters: [UUID: CheckedContinuation<Void, Error>] = [:]

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
        try await acquireReaderSlot()
        defer { releaseReaderSlot() }
        try await postAcquireReaderSlotHook?()
        return try Self.fetchAllProjects(in: modelContainer)
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

    /// See `ProjectRepository`'s doc comment for why this exists alongside
    /// plain `update(_:)`: `transform` runs against the truly-current
    /// persisted `Project`, fetched and written back as one operation
    /// serialized through the same `enqueueWrite`/`writeTails` mechanism as
    /// every other write for `id` — closing the fetch-then-write race a
    /// caller-side "fetch, build a modified copy, call `update(_:)`" pattern
    /// is exposed to.
    @discardableResult
    public func update(
        id: Project.ID,
        transform: @escaping @Sendable (Project) throws -> Project
    ) async throws -> Project? {
        let result: UpdateResult? =
            try await enqueueWrite(for: id) { [self, writeHook] () async throws -> UpdateResult? in
                await writeHook?(id)
                guard let current = try Self.fetchProject(id: id, in: self.modelContainer) else {
                    return nil
                }
                let updated = try transform(current)
                let snapshot = try await self.upsertProjectAndFetchSnapshot(updated)
                return UpdateResult(updated: updated, snapshot: snapshot)
            }
        guard let result else { return nil }
        publish(result.snapshot)
        return result.updated
    }

    /// Named instead of an anonymous tuple purely to keep the closure
    /// signature above under this project's line-length limit — no
    /// behavior reason to prefer one over the other.
    private struct UpdateResult: Sendable {
        let updated: Project
        let snapshot: [Project]
    }

    public func delete(id: Project.ID) async throws {
        let snapshot = try await enqueueWrite(for: id) { [self, writeHook] in
            await writeHook?(id)
            return try await deleteProjectAndFetchSnapshot(id: id)
        }
        publish(snapshot)
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
        let snapshot = try await enqueueWrite(for: project.id) { [self, writeHook] in
            await writeHook?(project.id)
            return try await upsertProjectAndFetchSnapshot(project)
        }
        publish(snapshot)
    }

    /// See the type's doc comment — the critical section below (reading
    /// `writeTails[id]`, building `resultTask`/`chainTask`, writing
    /// `writeTails[id]` back) is deliberately free of any `await`, which is
    /// what makes same-ID writes serialize while different-ID writes don't
    /// block each other.
    ///
    /// Generic over `work`'s return type so `update(id:transform:)` (which
    /// needs to hand its caller back the `Project` it just persisted) can
    /// share this exact same serialization mechanism with `write`/`delete`
    /// (which don't need a return value) — one queue per `Project.ID`, not
    /// two parallel ones that could reorder relative to each other.
    /// `writeTails` itself stays typed `Task<Void, Error>`: `resultTask` is
    /// the one callers actually await for a value, `chainTask` is a
    /// `Void`-typed wrapper around it purely so it can still be stored/read
    /// as `writeTails[id]` and chained onto by the next call for this `id`.
    private func enqueueWrite<T: Sendable>(
        for id: Project.ID,
        work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let previousTail = writeTails[id]
        let resultTask = Task<T, Error> {
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
            // to *its own* caller, via `resultTask.value` below — this only
            // stops it from also sabotaging writes that have nothing to do
            // with it.
            _ = try? await previousTail?.value
            return try await work()
        }
        writeTails[id] = Task<Void, Error> {
            _ = try? await resultTask.value
        }
        // --- end of critical section; the await below may suspend freely ---
        return try await resultTask.value
    }

    // MARK: - Subscribers

    private func register(_ continuation: AsyncStream<[Project]>.Continuation, as subscriberID: UUID) async {
        subscribers[subscriberID] = continuation
        guard await (try? acquireReaderSlot()) != nil else { return }
        defer { releaseReaderSlot() }
        if let snapshot = try? Self.fetchAllProjects(in: modelContainer) {
            continuation.yield(snapshot)
        }
    }

    private func unregister(_ subscriberID: UUID) {
        subscribers.removeValue(forKey: subscriberID)
    }

    private func publish(_ snapshot: [Project]) {
        for continuation in subscribers.values {
            continuation.yield(snapshot)
        }
    }
}
