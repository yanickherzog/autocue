import ACCore
import SwiftData

/// Confines every `ModelContext` access for one logical repository
/// operation to a single `@ModelActor`-backed serial executor, instead of
/// touching a raw, non-`Sendable` `ModelContext` from `nonisolated` code
/// across suspension points a `Task` is not guaranteed to resume from on
/// the same OS thread. `@ModelActor` is SwiftData's own mechanism for this
/// exact confinement contract.
///
/// **Always constructed fresh, once per call site's own operation — never
/// shared or stored across calls.** A single shared instance would
/// serialize every call routed through it (Swift actor isolation
/// guarantees mutual exclusion for calls to the *same* instance); nothing
/// in this project's crash evidence ever implicates reader-vs-reader or
/// writer-vs-writer concurrency between *different* `Project.ID`s, so a
/// shared executor would be a real regression, not a stronger fix — see
/// `docs/DECISIONS.md` for the confirming experiment that specifically
/// settled this (a fresh per-call instance reached 0 failures across
/// 12,600 iterations; a shared instance was never adopted or tested,
/// precisely because it would just be a second, disguised form of the
/// global write serialization `CLAUDE.md`'s "Document & Window Model"
/// already rejects).
///
/// `prepareUpsert`/`prepareDelete` deliberately stop short of calling
/// `save()` themselves — the caller (`ProjectRepositoryImpl
/// +ReaderWriterBarrier.swift`) brackets only the separate `save()` call
/// with the global save lock (`ProjectRepositoryImpl.isSavingGlobally`),
/// never the surrounding fetch/delete/insert mutation-building, matching
/// that lock's own narrow scope exactly. The gap between these calls (a
/// real suspension, while the global lock is acquired) does not break
/// confinement: every individual `ModelContext` touch still only ever
/// happens while isolated to *this* actor instance, regardless of how many
/// separate `await`-separated calls reach it over time.
@ModelActor
actor ProjectStoreExecutor {
    func prepareUpsert(_ project: Project) throws {
        if let existing = try ProjectRepositoryImpl.fetchEntity(id: project.id, in: modelContext) {
            modelContext.delete(existing)
        }
        modelContext.insert(ProjectMapper.toEntity(project))
    }

    /// Returns whether an entity existed to delete — `deleteProjectAndFetchSnapshot`
    /// only needs to call `save()` (and only then take the global save lock
    /// for it) when something was actually deleted, matching the baseline's
    /// own `if let existing = ...` guard around its `save()` call.
    func prepareDelete(id: Project.ID) throws -> Bool {
        guard let existing = try ProjectRepositoryImpl.fetchEntity(id: id, in: modelContext) else {
            return false
        }
        modelContext.delete(existing)
        return true
    }

    func save() throws {
        try modelContext.save()
    }

    func fetchSnapshot() throws -> [Project] {
        let entities = try modelContext.fetch(FetchDescriptor<ProjectEntity>())
        return try entities.map(ProjectMapper.toDomain)
    }

    func fetchOne(id: Project.ID) throws -> Project? {
        guard let entity = try ProjectRepositoryImpl.fetchEntity(id: id, in: modelContext) else {
            return nil
        }
        return try ProjectMapper.toDomain(entity)
    }
}
