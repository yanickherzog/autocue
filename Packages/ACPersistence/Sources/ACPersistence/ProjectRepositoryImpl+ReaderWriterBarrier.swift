import ACCore
import Foundation
import SwiftData

// MARK: - Reader/writer barrier

//
// Guards `fetchAllProjects`'s materialization of every project's full
// entity graph — used by a writer's own post-write snapshot (below),
// `register`'s initial snapshot, and the public `fetchAll()` — against
// any concurrent write for *any* `Project.ID`, not just the one that
// triggered the fetch. See `ProjectRepositoryImpl`'s doc comment for the
// crash this closes.
//
// A classic reader/writer lock, deliberately *not* a return to
// serializing all writes globally (`CLAUDE.md`'s "Document & Window
// Model" already rejected that once, for the exact multi-window reason
// it would reintroduce here): any number of writers for *different*
// `Project.ID`s still run fully concurrently with each other, exactly as
// before — `writeTails` is untouched by any of this. The only new
// blocking is writer-vs-reader — a write waits only if an all-projects
// fetch is actively in flight, and a fetch waits only if some write is
// actively mutating — both brief, one-shot conditions in this app's
// actual usage (fetches are triggered once per write or once per new
// subscription, never a standing/repeated operation), not a bottleneck.
//
// **Why the writer slot brackets only the mutation, not a writer's own
// follow-up fetch too:** a writer's own snapshot fetch is itself a
// reader. If it acquired a reader slot while still holding its own
// writer slot, `acquireReaderSlot`'s `activeWriterCount == 0` condition
// could never be satisfied by a count that includes itself — a
// guaranteed self-deadlock on every single write. The writer slot is
// therefore released before the reader slot for that same operation's
// own fetch is acquired — see `upsertProjectAndFetchSnapshot`/
// `deleteProjectAndFetchSnapshot`, below.
//
// **Cancellation:** waiters are keyed by `UUID` in a dictionary, not
// held in an array — `withTaskCancellationHandler`'s `onCancel` closure
// is synchronous and can't itself touch actor state, so it dispatches a
// small `Task` back onto the actor to remove-and-resume the specific
// waiter. That path and the normal wake-up path in
// `releaseWriterSlot`/`releaseReaderSlot` both use the same idempotent
// `removeValue(forKey:)` before resuming, so whichever runs first empties
// the slot and the other finds nothing to do — no continuation is ever
// resumed twice (a hard trap if it were).
//
// This lives in its own file, as an extension of `ProjectRepositoryImpl`,
// purely to keep the main file under this project's line-length limit —
// the state these methods touch (`activeWriterCount`/`writerWaiters`/
// `activeReaderCount`/`readerWaiters`/the two test-only hooks) is declared
// in the primary type body in `ProjectRepositoryImpl.swift` (Swift
// extensions can't add stored properties) at `internal` visibility so this
// file can reach it — still fully contained within the `ACPersistence`
// module, never exposed to any other package.
extension ProjectRepositoryImpl {
    func setPostAcquireWriterSlotHook(_ hook: (@Sendable () async throws -> Void)?) {
        postAcquireWriterSlotHook = hook
    }

    func setPostAcquireReaderSlotHook(_ hook: (@Sendable () async throws -> Void)?) {
        postAcquireReaderSlotHook = hook
    }

    /// Actor-isolated crossing point for `upsertProjectAndFetchSnapshot`/
    /// `deleteProjectAndFetchSnapshot` (both `nonisolated`) to invoke the
    /// test-only writer hook without directly reading a mutable
    /// actor-isolated `var` from off-actor code.
    func firePostAcquireWriterSlotHook() async throws {
        try await postAcquireWriterSlotHook?()
    }

    /// See `firePostAcquireWriterSlotHook`'s comment — same reason, reader side.
    func firePostAcquireReaderSlotHook() async throws {
        try await postAcquireReaderSlotHook?()
    }

    func acquireWriterSlot() async throws {
        guard activeReaderCount > 0 else {
            activeWriterCount += 1
            return
        }
        let waiterID = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { writerWaiters[waiterID] = $0 }
        } onCancel: {
            Task { await self.cancelWriterWait(waiterID) }
        }
        activeWriterCount += 1
    }

    func releaseWriterSlot() {
        activeWriterCount -= 1
        guard activeWriterCount == 0 else { return }
        let waiters = readerWaiters
        readerWaiters.removeAll()
        waiters.values.forEach { $0.resume() }
    }

    func cancelWriterWait(_ waiterID: UUID) {
        writerWaiters.removeValue(forKey: waiterID)?.resume(throwing: CancellationError())
    }

    func acquireReaderSlot() async throws {
        guard activeWriterCount > 0 else {
            activeReaderCount += 1
            return
        }
        let waiterID = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { readerWaiters[waiterID] = $0 }
        } onCancel: {
            Task { await self.cancelReaderWait(waiterID) }
        }
        activeReaderCount += 1
    }

    func releaseReaderSlot() {
        activeReaderCount -= 1
        guard activeReaderCount == 0 else { return }
        let waiters = writerWaiters
        writerWaiters.removeAll()
        waiters.values.forEach { $0.resume() }
    }

    func cancelReaderWait(_ waiterID: UUID) {
        readerWaiters.removeValue(forKey: waiterID)?.resume(throwing: CancellationError())
    }
}

// MARK: - SwiftData work (nonisolated: safe to run inside a dispatched `Task`, off the actor)

extension ProjectRepositoryImpl {
    static func fetchAllProjects(in container: ModelContainer) throws -> [Project] {
        let context = ModelContext(container)
        let entities = try context.fetch(FetchDescriptor<ProjectEntity>())
        return try entities.map(ProjectMapper.toDomain)
    }

    static func fetchProject(id: Project.ID, in container: ModelContainer) throws -> Project? {
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
    ///
    /// **Returns the post-save snapshot fetched from this same `context`,
    /// deliberately never a fresh, independent one, and only once the
    /// reader/writer barrier's reader slot is held** (see the "Reader/writer
    /// barrier" section above for why the writer slot is released first).
    /// Two real crashes were reproduced (2026-09-05, see
    /// `docs/DECISIONS.md`): a same-`Project.ID` one, where a subsequent
    /// write's delete-and-reinsert invalidated an entity an independent
    /// context had already fetched but not finished materializing, closed by
    /// same-context read-after-write; and a cross-project one, where this
    /// snapshot's own fetch raced a *different* project's concurrent write,
    /// closed by the barrier. `SwiftData/BackingData.swift`'s "invalidated
    /// because its backing data could no longer be found in the store" is
    /// the shared symptom of both.
    ///
    /// No `defer` for either slot's release: this method is `nonisolated`
    /// (it must run off the actor so different `Project.ID` writes stay
    /// genuinely concurrent), so releasing a slot means hopping back onto
    /// the actor via `await` — not something a plain `defer` can do
    /// synchronously at this function's exit. Every exit path (success and
    /// thrown error) releases explicitly instead.
    nonisolated func upsertProjectAndFetchSnapshot(_ project: Project) async throws -> [Project] {
        try await acquireWriterSlot()
        let context = ModelContext(modelContainer)
        do {
            try await firePostAcquireWriterSlotHook()
            if let existing = try Self.fetchEntity(id: project.id, in: context) {
                context.delete(existing)
            }
            context.insert(ProjectMapper.toEntity(project))
            try context.save()
        } catch {
            await releaseWriterSlot()
            throw error
        }
        await releaseWriterSlot()

        try await acquireReaderSlot()
        do {
            try await firePostAcquireReaderSlotHook()
            let entities = try context.fetch(FetchDescriptor<ProjectEntity>())
            let snapshot = try entities.map(ProjectMapper.toDomain)
            await releaseReaderSlot()
            return snapshot
        } catch {
            await releaseReaderSlot()
            throw error
        }
    }

    /// See `upsertProjectAndFetchSnapshot`'s doc comment — same-context
    /// read-after-write behind the reader/writer barrier, for the same
    /// reason.
    nonisolated func deleteProjectAndFetchSnapshot(id: Project.ID) async throws -> [Project] {
        try await acquireWriterSlot()
        let context = ModelContext(modelContainer)
        do {
            try await firePostAcquireWriterSlotHook()
            if let existing = try Self.fetchEntity(id: id, in: context) {
                context.delete(existing)
                try context.save()
            }
        } catch {
            await releaseWriterSlot()
            throw error
        }
        await releaseWriterSlot()

        try await acquireReaderSlot()
        do {
            try await firePostAcquireReaderSlotHook()
            let entities = try context.fetch(FetchDescriptor<ProjectEntity>())
            let snapshot = try entities.map(ProjectMapper.toDomain)
            await releaseReaderSlot()
            return snapshot
        } catch {
            await releaseReaderSlot()
            throw error
        }
    }

    static func fetchEntity(id: Project.ID, in context: ModelContext) throws -> ProjectEntity? {
        var descriptor = FetchDescriptor<ProjectEntity>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
