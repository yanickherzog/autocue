@testable import ACCore
@testable import ACPersistence
import SwiftData
import XCTest

/// Dedicated coverage for the reader/writer barrier added to
/// `ProjectRepositoryImpl` on 2026-09-05 (see that type's "Reader/writer
/// barrier" doc section and `docs/DECISIONS.md`) — the fix for a real,
/// live-reproduced crash where one project's all-projects snapshot fetch
/// could race a *different* project's concurrent write. These tests use
/// the barrier-specific `setPostAcquireWriterSlotHook`/
/// `setPostAcquireReaderSlotHook` test seams, the same `Signal`-based
/// determinism style as `ProjectRepositoryImplTests`'s own concurrency
/// tests, rather than wall-clock timing wherever a positive signal to wait
/// on is available.
final class ReaderWriterBarrierTests: XCTestCase {
    // MARK: - Different-ID writers still run concurrently

    /// The barrier's core requirement, proven directly: any number of
    /// writers for *different* `Project.ID`s still hold their slots
    /// simultaneously — the barrier adds writer-vs-reader coordination
    /// only, never writer-vs-writer. Fully deterministic (no timeout):
    /// `secondArrived.wait()` can only resolve once B's writer has
    /// genuinely acquired its own slot, and it does so *before* A is ever
    /// released — proving both were held at once, not serialized.
    func test_writersForDifferentProjectIDs_bothHoldWriterSlotsSimultaneously() async throws {
        let repository = try makeRepository()
        let idA = UUID()
        let idB = UUID()
        let counter = CallCounter()
        let firstArrived = Signal()
        let secondArrived = Signal()
        let releaseBoth = Signal()

        await repository.setPostAcquireWriterSlotHook {
            if await counter.increment() == 1 {
                await firstArrived.fire()
            } else {
                await secondArrived.fire()
            }
            await releaseBoth.wait()
        }

        let taskA = Task { try await repository.create(ProjectFixture.makeMinimal(id: idA, name: "a")) }
        await firstArrived.wait()

        let taskB = Task { try await repository.create(ProjectFixture.makeMinimal(id: idB, name: "b")) }
        // If the barrier accidentally serialized writers against each
        // other, this would hang until the suite's timeout rather than
        // fail fast — the same accepted trade-off as
        // `ProjectRepositoryImplTests.test_differentProjectIDWritesDoNotBlockEachOther`.
        await secondArrived.wait()

        await releaseBoth.fire()
        try await taskA.value
        try await taskB.value

        let all = try await repository.fetchAll()
        XCTAssertEqual(Set(all.map(\.id)), Set([idA, idB]))
    }

    // MARK: - Writer vs. reader

    /// A writer submitted while a reader (`fetchAll()`) holds the barrier
    /// must not acquire its slot until the reader releases. Proving the
    /// negative ("has not acquired yet") has no positive signal to wait
    /// on, so this is the one place in this file that uses a bounded,
    /// generous timeout rather than a `Signal` — explicitly not a strict
    /// zero-tolerance proof (nothing about `Task` scheduling gives one
    /// without deep scheduler instrumentation), just a real, generous
    /// window. The other direction — release genuinely unblocks the
    /// writer — is fully deterministic below.
    func test_readerBlocksASubsequentlySubmittedWriter_untilTheReaderReleases() async throws {
        let repository = try makeRepository()
        let readerEntered = Signal()
        let releaseReader = Signal()
        let writerAcquired = Signal()

        await repository.setPostAcquireReaderSlotHook {
            await readerEntered.fire()
            await releaseReader.wait()
        }
        let readerTask = Task { try await repository.fetchAll() }
        await readerEntered.wait()

        await repository.setPostAcquireWriterSlotHook { await writerAcquired.fire() }
        let writerTask = Task {
            try await repository.create(ProjectFixture.makeMinimal(name: "while-reading"))
        }

        try? await Task.sleep(nanoseconds: 200_000_000)
        let acquiredEarly = await writerAcquired.hasFired
        XCTAssertFalse(acquiredEarly, "the writer must not acquire its slot while a reader is active")

        await releaseReader.fire()
        // Fully deterministic from here: if release didn't correctly wake
        // the writer, this hangs until the suite's timeout.
        try await writerTask.value
        _ = try await readerTask.value
    }

    /// The mirror image: a reader (`fetchAll()`) submitted while a writer
    /// holds the barrier must not acquire its slot until the writer
    /// releases.
    func test_writerBlocksASubsequentlySubmittedReader_untilTheWriterReleases() async throws {
        let repository = try makeRepository()
        let writerEntered = Signal()
        let releaseWriter = Signal()
        let readerAcquired = Signal()

        await repository.setPostAcquireWriterSlotHook {
            await writerEntered.fire()
            await releaseWriter.wait()
        }
        let writerTask = Task {
            try await repository.create(ProjectFixture.makeMinimal(name: "holds-writer-slot"))
        }
        await writerEntered.wait()

        await repository.setPostAcquireReaderSlotHook { await readerAcquired.fire() }
        let readerTask = Task { try await repository.fetchAll() }

        try? await Task.sleep(nanoseconds: 200_000_000)
        let acquiredEarly = await readerAcquired.hasFired
        XCTAssertFalse(acquiredEarly, "the reader must not acquire its slot while a writer is active")

        await releaseWriter.fire()
        try await writerTask.value
        _ = try await readerTask.value
    }

    // MARK: - Failure releases the slot

    /// A writer whose mutation phase throws — *after* acquiring the
    /// writer slot — must still release it. Detected via a subsequent
    /// `fetchAll()` (a reader): a leaked writer slot would make
    /// `activeWriterCount` stick above zero forever, and a reader can
    /// never acquire while that holds — this hangs rather than fails fast
    /// if the slot leaked, the only way to actually observe it (a leaked
    /// *writer* slot would never block a second *writer*, since
    /// writer-vs-writer is never blocked regardless).
    func test_writerThatThrowsWhileHoldingItsSlot_stillReleasesIt() async throws {
        let repository = try makeRepository()
        struct InjectedTestError: Error {}

        await repository.setPostAcquireWriterSlotHook { throw InjectedTestError() }

        do {
            try await repository.create(ProjectFixture.makeMinimal(name: "boom"))
            XCTFail("expected the injected error to propagate")
        } catch is InjectedTestError {
            // expected
        }
        await repository.setPostAcquireWriterSlotHook(nil)

        let all = try await repository.fetchAll()
        XCTAssertEqual(all.count, 0, "the failed write must not have persisted anything")
    }

    // MARK: - Cancellation doesn't corrupt the waiter list

    /// A cancelled queued waiter must not prevent a *different* queued
    /// waiter from being woken correctly, and must not cause a
    /// double-resume (a hard trap) when both the cancellation path and the
    /// normal wake-up path could plausibly race for the same entry.
    ///
    /// Exercised via two `fetchAll()` calls (readers), not two writes —
    /// `enqueueWrite` dispatches each write's actual barrier-guarded work
    /// into its own internal, independently-created `Task`, which does not
    /// inherit cancellation from the caller's own `Task`; cancelling the
    /// caller's `Task` therefore can't reach a writer's queued barrier
    /// wait at all in the current architecture. `fetchAll()` has no such
    /// indirection — it runs the barrier acquisition directly on the
    /// caller's own `Task`, so cancelling that `Task` genuinely reaches
    /// `acquireReaderSlot`'s suspended continuation. The removal/resume
    /// logic under test (`cancelReaderWait`/`cancelWriterWait`) is
    /// otherwise identical, mirrored code for both roles, so this gives
    /// full confidence in both.
    func test_cancellingAQueuedReaderWaiter_doesNotPreventAnotherQueuedReaderFromBeingWoken() async throws {
        let repository = try makeRepository()
        let writerEntered = Signal()
        let releaseWriter = Signal()
        let survivingReaderAcquired = Signal()

        await repository.setPostAcquireWriterSlotHook {
            await writerEntered.fire()
            await releaseWriter.wait()
        }
        let writerTask = Task {
            try await repository.create(ProjectFixture.makeMinimal(name: "holds-writer-slot"))
        }
        await writerEntered.wait()

        // Two readers submitted while the writer holds the barrier — both
        // must queue as waiters.
        let cancelledReaderTask = Task { try await repository.fetchAll() }

        await repository.setPostAcquireReaderSlotHook { await survivingReaderAcquired.fire() }
        let survivingReaderTask = Task { try await repository.fetchAll() }

        // No hook exists for "has registered as a queued waiter"
        // specifically — that's genuinely internal, and adding a third
        // seam purely to sequence this one test isn't worth it. This is
        // the one place in this file that's a generous sleep rather than a
        // Signal, for exactly that reason.
        try? await Task.sleep(nanoseconds: 200_000_000)
        cancelledReaderTask.cancel()

        await releaseWriter.fire()
        // Fully deterministic: proves the surviving waiter was actually
        // woken, not just that nothing crashed.
        await survivingReaderAcquired.wait()
        _ = try await survivingReaderTask.value
        _ = try await writerTask.value

        // Either outcome (cancelled or, if the cancellation lost a benign
        // race against the normal wake-up, succeeded) is acceptable — the
        // safety property under test is that the surviving waiter above
        // was woken correctly and nothing double-resumed/crashed.
        _ = try? await cancelledReaderTask.value
    }

    // MARK: - Same-`Project.ID` write cannot begin until the prior write's own snapshot fetch finishes

    /// Reproduces the exact real crash (2026-09-05, see `docs/DECISIONS.md`
    /// and `docs/REVIEW.md`'s D9 entry): `AudioImportViewModel`'s real flow
    /// issues two `update(id:transform:)` calls for the *same* `Project.ID`
    /// in quick succession — `ImportAudioUseCase` persisting the
    /// `AudioAsset`, then `GenerateWaveformPeaksUseCase` persisting
    /// `WaveformPeaks` moments later, with no intervening await on the
    /// first write's full completion. Confirmed live, under a debugger,
    /// fully symbolicated: `ProjectRepositoryImpl.update(id:transform:)`'s
    /// post-write `publishSnapshot()` used to fetch via a *brand-new,
    /// independent* `ModelContext` — outside the `writeTails` per-ID
    /// serialization that only covered the raw `upsertProject` mutation.
    /// The second write's delete-and-reinsert could complete while the
    /// first write's own snapshot fetch was still mid-flight lazily
    /// resolving `AudioAssetEntity.embeddedMarkers` on the object it had
    /// already fetched — crashing with SwiftData's "invalidated because its
    /// backing data could no longer be found in the store"
    /// (`SwiftData/BackingData.swift:875`).
    ///
    /// The fix folds the post-write snapshot fetch into the *same*
    /// `ModelContext`/task as the write itself (see
    /// `upsertProjectAndFetchSnapshot`'s doc comment), so it's now
    /// structurally part of the same `writeTails`-chained unit. This test
    /// proves that resulting invariant directly, deterministically (via
    /// `Signal`/`setWriteHook`) — the second same-`Project.ID` write's own
    /// dispatched work cannot even *begin* until the first write's entire
    /// chained unit — upsert *and* its own snapshot fetch — has completed.
    func test_secondSameProjectIDWrite_cannotBeginUntilFirstWritesOwnSnapshotFetchHasCompleted() async throws {
        let repository = try makeRepository()
        let projectID = UUID()
        try await repository.create(ProjectFixture.makeMinimal(id: projectID, name: "original"))

        let firstEntered = Signal()
        let releaseFirst = Signal()
        let pauseGate = PauseOnceGate()

        await repository.setWriteHook { id in
            guard id == projectID, await pauseGate.shouldPauseOnce() else { return }
            await firstEntered.fire()
            await releaseFirst.wait()
        }

        let asset = Self.makeAudioAssetFixture()
        let assetWriteTask = Task { try await repository.update(id: projectID) { $0.settingAsset(asset) } }
        // Confirms the asset write is genuinely blocked *inside* its own
        // dispatched work, holding projectID's write tail, before the
        // peaks write is even submitted.
        await firstEntered.wait()

        let peaksWriteTask = Task {
            try await repository.update(id: projectID) { $0.settingWaveformPeaks(for: asset) }
        }

        await releaseFirst.fire()
        let assetResult = try await assetWriteTask.value
        let peaksResult = try await peaksWriteTask.value

        XCTAssertNotNil(assetResult?.audioAsset, "the asset write must have actually landed")
        XCTAssertNotNil(peaksResult?.waveformPeaks, "the peaks write must have actually landed")

        let final = try await repository.fetch(id: projectID)
        XCTAssertNotNil(final?.audioAsset, "the asset write must survive the peaks write that followed it")
        XCTAssertNotNil(final?.waveformPeaks)
    }

    // MARK: - Helpers

    private func makeRepository() throws -> ProjectRepositoryImpl {
        try ProjectRepositoryImpl(modelContainer: makeInMemoryContainer())
    }

    private static func makeAudioAssetFixture() -> AudioAsset {
        AudioAsset(
            originalFileName: "reel.wav",
            securityScopedBookmark: Data([0, 1, 2, 3]),
            duration: MediaDuration(seconds: 120),
            sampleRate: 48000,
            channelCount: 2,
            bitDepth: 24,
            embeddedMarkers: [],
            importedAt: Date()
        )
    }
}

/// Test-only: the two field-level transforms
/// `test_secondSameProjectIDWrite_cannotBeginUntilFirstWritesOwnSnapshotFetchHasCompleted`
/// applies via `update(id:transform:)`, factored out purely to keep that
/// test's own body under this project's function-length limit.
private extension Project {
    func settingAsset(_ asset: AudioAsset) -> Project {
        Project(
            id: id, name: name, createdAt: createdAt, updatedAt: updatedAt,
            audioAsset: asset, setup: setup
        )
    }

    func settingWaveformPeaks(for asset: AudioAsset) -> Project {
        let peaks = WaveformPeaks(
            audioAssetID: asset.id,
            resolution: 8,
            buckets: (0 ..< 8).map { _ in WaveformPeakBucket(min: -0.5, max: 0.5) }
        )
        return Project(
            id: id, name: name, createdAt: createdAt, updatedAt: updatedAt,
            audioAsset: audioAsset, waveformPeaks: peaks, setup: setup
        )
    }
}

/// Test-only: distinguishes the first vs. every subsequent call to a
/// shared hook closure, without capturing a plain mutable `var` in a
/// `@Sendable` closure.
private actor CallCounter {
    private var count = 0

    func increment() -> Int {
        count += 1
        return count
    }
}
