@testable import ACCore
@testable import ACPersistence
import ACTestSupport
import XCTest

/// Dedicated coverage for closing a real, separate exposure found while
/// root-causing `ReaderWriterBarrierTests`' writer-vs-writer `save()` race
/// (`docs/DECISIONS.md`, 2026-10-05): `fetch(id:)` and the first line of
/// `update(id:transform:)`'s closure both called `Self.fetchProject` with
/// zero reader/writer barrier protection at all, even though every other
/// full-graph materialization in `ProjectRepositoryImpl` goes through the
/// reader slot. Not implicated in the crash this project traced to
/// writer-vs-writer `save()` collisions — neither bypass was ever on that
/// crashing stack — but closed regardless, since it's a real production
/// exposure independent of that root cause. Split into its own file
/// (rather than added to `ReaderWriterBarrierTests.swift`) purely to stay
/// under this project's file-length limit.
final class FetchByIDBypassTests: XCTestCase {
    /// `fetch(id:)` submitted while a writer holds the barrier must not
    /// acquire its own reader slot until the writer releases — the same
    /// shape as `ReaderWriterBarrierTests.test_writerBlocksASubsequentlySubmittedReader_untilTheWriterReleases`,
    /// applied to this specific call site now that it's barrier-protected.
    func test_fetchByID_waitsForAnInFlightWriter_beforeItsOwnReadBegins() async throws {
        let repository = try makeRepository()
        let projectID = UUID()
        try await repository.create(ProjectFixture.makeMinimal(id: projectID, name: "original"))

        let writerEntered = Signal()
        let releaseWriter = Signal()
        let readerAcquired = Signal()

        await repository.setPostAcquireWriterSlotHook {
            await writerEntered.fire()
            await releaseWriter.wait()
        }
        let writerTask = Task {
            try await repository.update(id: projectID) { $0 }
        }
        await writerEntered.wait()

        await repository.setPostAcquireReaderSlotHook { await readerAcquired.fire() }
        let fetchTask = Task { try await repository.fetch(id: projectID) }

        try? await Task.sleep(nanoseconds: 200_000_000)
        let acquiredEarly = await readerAcquired.hasFired
        XCTAssertFalse(acquiredEarly, "fetch(id:) must not acquire its reader slot while a writer is active")

        await releaseWriter.fire()
        // Fully deterministic from here: if release didn't correctly wake
        // fetch(id:)'s reader wait, this hangs until the suite's timeout.
        _ = try await writerTask.value
        let fetched = try await fetchTask.value
        XCTAssertNotNil(fetched)
    }

    /// Proves the fix cannot deadlock: `update(id:transform:)`'s own
    /// initial read takes a reader slot and must release it *before* its
    /// later `upsertProjectAndFetchSnapshot` call ever requests a writer
    /// slot for the same logical operation — never both held at once by
    /// the same caller. Observed directly via the reader hook firing (the
    /// initial read genuinely acquires the barrier) followed by the writer
    /// hook firing (the write phase genuinely acquires it too) for the
    /// *same* `update(id:transform:)` call, with the whole call completing
    /// — if the reader slot were still held when the writer slot was
    /// requested, `acquireWriterSlot`'s `activeReaderCount == 0` condition
    /// could never be satisfied by a count that includes itself, and this
    /// would hang forever rather than fail fast.
    func test_updateIDTransform_releasesItsReaderSlotBeforeRequestingAWriterSlot_doesNotDeadlock() async throws {
        let repository = try makeRepository()
        let projectID = UUID()
        try await repository.create(ProjectFixture.makeMinimal(id: projectID, name: "original"))

        let readerAcquired = Signal()
        let writerAcquired = Signal()
        await repository.setPostAcquireReaderSlotHook { await readerAcquired.fire() }
        await repository.setPostAcquireWriterSlotHook { await writerAcquired.fire() }

        let result = try await repository.update(id: projectID) { project in
            Project(
                id: project.id, name: "renamed", createdAt: project.createdAt,
                updatedAt: project.updatedAt, setup: project.setup
            )
        }

        // `update(id:transform:)` has already fully returned at this point
        // — structured concurrency guarantees everything it awaited
        // internally, including both hooks below, already ran. `hasFired`
        // is reliable here (unlike a "has NOT happened yet" check elsewhere
        // in this suite): it confirms both the reader slot (the initial
        // read) and the writer slot (the upsert) were genuinely acquired
        // during this one call, for the same operation, in sequence — not
        // just that the call happened to return.
        let readDidAcquireReaderSlot = await readerAcquired.hasFired
        let writeDidAcquireWriterSlot = await writerAcquired.hasFired
        XCTAssertTrue(readDidAcquireReaderSlot, "the initial read must have taken the reader slot")
        XCTAssertTrue(writeDidAcquireWriterSlot, "the upsert must have taken the writer slot")
        XCTAssertEqual(result?.name, "renamed")

        let final = try await repository.fetch(id: projectID)
        XCTAssertEqual(final?.name, "renamed")
    }

    // MARK: - Helpers

    private func makeRepository() throws -> ProjectRepositoryImpl {
        try ProjectRepositoryImpl(modelContainer: makeInMemoryContainer())
    }
}
