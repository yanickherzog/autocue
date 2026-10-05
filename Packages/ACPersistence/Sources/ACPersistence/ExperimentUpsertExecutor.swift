import ACCore
import SwiftData

// EXPERIMENT 4 (temporary, CI-only — not for `main`): thread-confinement
// test. `ModelContext` is not `Sendable`; in the baseline
// `upsertProjectAndFetchSnapshot`/`deleteProjectAndFetchSnapshot`, the same
// `context` value is used before AND after `await releaseWriterSlot()` /
// `await acquireReaderSlot()` — two genuine suspension points a `Task` is
// not guaranteed to resume from on the same OS thread. This type confines
// that same `ModelContext` to a `@ModelActor`-backed serial executor
// instead of touching it directly from `nonisolated` code, so every access
// — the mutate+save phase and, later, the fetch+map phase — runs via the
// actor's own underlying queue confinement (the exact mechanism `@ModelActor`
// exists to provide), regardless of which OS thread happens to be running
// the calling `Task` at that moment.
//
// **Deliberately preserves the baseline reader/writer barrier's structure
// and timing exactly** — writer slot held only across `mutateAndSave`,
// released, then the reader slot acquired for `fetchSnapshot` — so this
// experiment changes exactly one variable (how the `ModelContext` itself is
// isolated) and nothing about barrier protection. A single executor
// instance is constructed once per operation and both phases are called on
// that same instance, so it's the same underlying context both times, not
// two independent ones.
//
// See docs/DECISIONS.md.
@ModelActor
actor ExperimentUpsertExecutor {
    func mutateAndSave(_ project: Project) throws {
        if let existing = try ProjectRepositoryImpl.fetchEntity(id: project.id, in: modelContext) {
            modelContext.delete(existing)
        }
        modelContext.insert(ProjectMapper.toEntity(project))
        try modelContext.save()
    }

    func deleteAndSave(id: Project.ID) throws {
        if let existing = try ProjectRepositoryImpl.fetchEntity(id: id, in: modelContext) {
            modelContext.delete(existing)
            try modelContext.save()
        }
    }

    func fetchSnapshot() throws -> [Project] {
        let entities = try modelContext.fetch(FetchDescriptor<ProjectEntity>())
        return try entities.map(ProjectMapper.toDomain)
    }
}
