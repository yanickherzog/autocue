import ACCore
@testable import ACPersistence
import SwiftData
import XCTest

/// Reproduces the real crash reported against the running app: importing
/// audio crashes inside `ProjectMapper.toDomain`/`AudioAssetMapper.toDomain`
/// — an assertion failure inside a SwiftData macro-generated
/// persisted-property getter.
///
/// **Confirmed root cause (2026-09-05, live under a debugger — see
/// `docs/DECISIONS.md`), superseding this file's original "second import"
/// framing:** it was never specifically about a *second* import — it's a
/// race inside a *single* import's own two-write sequence
/// (`ImportAudioUseCase` persists the `AudioAsset`, then
/// `GenerateWaveformPeaksUseCase` persists `WaveformPeaks` moments later,
/// both against the same `Project.ID`). The first write's own
/// `publishSnapshot()` used to fetch via a brand-new, independent
/// `ModelContext`, outside the `writeTails` per-ID serialization that only
/// covered the raw `upsertProject` mutation; the second write's
/// delete-and-reinsert could complete while the first write's snapshot
/// fetch was still mid-flight lazily resolving a fault — `SwiftData
/// /BackingData.swift:875`'s "invalidated because its backing data could
/// no longer be found in the store." The tests below were written *before*
/// the real mechanism was confirmed and, being purely sequential (each
/// import fully `await`ed before the next began), did **not** reproduce it
/// — kept as a baseline (sequential imports must never crash either); the
/// concurrency-exercising test at the bottom of this file is the one that
/// actually targets the confirmed race. Uses a **real on-disk**
/// `ModelContainer` (not the in-memory fakes every other
/// `ACPersistenceTests` file uses) — the crash was only ever observed
/// against the real app's on-disk store.
final class SecondImportCrashReproTests: XCTestCase {
    private var storeURL: URL!

    override func setUpWithError() throws {
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SecondImportCrashRepro-\(UUID().uuidString).sqlite")
    }

    override func tearDownWithError() throws {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
        }
    }

    private func makeOnDiskContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(url: storeURL)
        return try ModelContainer(for: ProjectRepositoryImpl.makeSchema(), configurations: configuration)
    }

    private func makeSetup() -> Setup {
        Setup(
            title: "A Swiss Story",
            productionRuntime: .zero,
            totalMusicRuntime: .zero,
            productionYear: 2026,
            containsAdditionalUndeclaredWorks: .no,
            productionTypes: [.documentaryFilm],
            declarationDate: Date(timeIntervalSince1970: 0)
        )
    }

    private func makeAudioAsset(markerCount: Int) -> AudioAsset {
        AudioAsset(
            originalFileName: "reel.wav",
            securityScopedBookmark: Data([0, 1, 2, 3]),
            duration: MediaDuration(seconds: 120),
            sampleRate: 48000,
            channelCount: 2,
            bitDepth: 24,
            embeddedMarkers: (0 ..< markerCount).map { index in
                EmbeddedMarker(position: Timecode(offsetSeconds: Double(index) * 10), label: "Marker \(index)")
            },
            importedAt: Date()
        )
    }

    private func makeWaveformPeaks(for assetID: AudioAsset.ID) -> WaveformPeaks {
        WaveformPeaks(
            audioAssetID: assetID,
            resolution: 8,
            buckets: (0 ..< 8).map { _ in WaveformPeakBucket(min: -0.5, max: 0.5) }
        )
    }

    /// Mirrors `AudioImportViewModel.importFile(from:)`'s real sequence:
    /// `ImportAudioUseCase` persists `audioAsset` first (one
    /// `update(id:transform:)` call), then `GenerateWaveformPeaksUseCase`
    /// persists `waveformPeaks` immediately after (a second
    /// `update(id:transform:)` call) — each one triggering
    /// `publishSnapshot()`'s `fetchAll` right after it.
    private func simulateOneImport(
        repository: ProjectRepositoryImpl,
        projectID: Project.ID,
        markerCount: Int
    ) async throws {
        let asset = makeAudioAsset(markerCount: markerCount)
        _ = try await repository.update(id: projectID) { project in
            Project(
                id: project.id,
                name: project.name,
                createdAt: project.createdAt,
                updatedAt: Date(),
                audioAsset: asset,
                waveformPeaks: project.waveformPeaks,
                setup: project.setup,
                cues: project.cues,
                people: project.people,
                labels: project.labels
            )
        }
        let peaks = makeWaveformPeaks(for: asset.id)
        _ = try await repository.update(id: projectID) { project in
            Project(
                id: project.id,
                name: project.name,
                createdAt: project.createdAt,
                updatedAt: Date(),
                audioAsset: project.audioAsset,
                waveformPeaks: peaks,
                setup: project.setup,
                cues: project.cues,
                people: project.people,
                labels: project.labels
            )
        }
    }

    /// Case 1 from the bug report: re-importing into the **same** Project.
    func test_reimportingIntoTheSameProject_secondImportDoesNotCrashOrThrow() async throws {
        let container = try makeOnDiskContainer()
        let repository = ProjectRepositoryImpl(modelContainer: container)
        let project = Project(
            name: "Reel One",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            setup: makeSetup()
        )
        try await repository.create(project)

        try await simulateOneImport(repository: repository, projectID: project.id, markerCount: 3)
        try await simulateOneImport(repository: repository, projectID: project.id, markerCount: 5)

        let fetched = try await repository.fetchAll()
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.audioAsset?.embeddedMarkers.count, 5)
    }

    /// Case 2 from the bug report: a second import into a **brand-new**
    /// Project, with the first Project's already-imported audio still in
    /// the store.
    func test_importingIntoASecondNewProject_doesNotCrashOrThrow() async throws {
        let container = try makeOnDiskContainer()
        let repository = ProjectRepositoryImpl(modelContainer: container)
        let projectA = Project(
            name: "Reel One",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            setup: makeSetup()
        )
        let projectB = Project(
            name: "Reel Two",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            setup: makeSetup()
        )
        try await repository.create(projectA)
        try await repository.create(projectB)

        try await simulateOneImport(repository: repository, projectID: projectA.id, markerCount: 3)
        try await simulateOneImport(repository: repository, projectID: projectB.id, markerCount: 5)

        let fetched = try await repository.fetchAll()
        XCTAssertEqual(fetched.count, 2)
    }

    /// The test that actually targets the confirmed race, on a real on-disk
    /// store: the asset write and the peaks write are launched via separate
    /// `Task`s with **no `await` on the first one's full completion**
    /// before the second is submitted — the same shape as
    /// `AudioImportViewModel`'s real flow, where `GenerateWaveformPeaksUseCase`
    /// is kicked off as soon as import succeeds, not after that call's own
    /// `publishSnapshot()` has necessarily finished. Repeated across many
    /// fresh, concurrently-imported projects to give real (uncontrolled,
    /// thread-pool-scheduled) concurrency a real chance to exercise the
    /// timing window the fix closes — a single trial proves little either
    /// way for a genuine race; this is the empirical complement to
    /// `ProjectRepositoryImplTests`'s deterministic, `Signal`-based proof of
    /// the same invariant.
    func test_manyProjectsImportedConcurrently_assetAndPeaksWritesNeverRace() async throws {
        let container = try makeOnDiskContainer()
        let repository = ProjectRepositoryImpl(modelContainer: container)
        let projectIDs = (0 ..< 20).map { _ in UUID() }

        for projectID in projectIDs {
            try await repository.create(Project(
                id: projectID,
                name: "Reel",
                createdAt: Date(timeIntervalSince1970: 0),
                updatedAt: Date(timeIntervalSince1970: 0),
                setup: makeSetup()
            ))
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for projectID in projectIDs {
                group.addTask {
                    try await self.importConcurrently(into: projectID, repository: repository)
                }
            }
            try await group.waitForAll()
        }

        let fetched = try await repository.fetchAll()
        XCTAssertEqual(fetched.count, projectIDs.count)
        for projectID in projectIDs {
            let project = fetched.first { $0.id == projectID }
            XCTAssertNotNil(project?.audioAsset, "project \(projectID)'s asset write must have landed")
        }
    }

    /// One project's asset-write-then-peaks-write pair, launched with no
    /// `await` on the asset write's full completion before the peaks write
    /// is submitted — deliberately, to mirror the real trigger's timing
    /// rather than the sequential `simulateOneImport` helper above.
    private func importConcurrently(into projectID: Project.ID, repository: ProjectRepositoryImpl) async throws {
        let asset = makeAudioAsset(markerCount: 3)
        async let assetWrite: Void = {
            _ = try await repository.update(id: projectID) { project in
                Project(
                    id: project.id,
                    name: project.name,
                    createdAt: project.createdAt,
                    updatedAt: Date(),
                    audioAsset: asset,
                    waveformPeaks: project.waveformPeaks,
                    setup: project.setup,
                    cues: project.cues,
                    people: project.people,
                    labels: project.labels
                )
            }
        }()
        async let peaksWrite: Void = {
            _ = try await repository.update(id: projectID) { project in
                Project(
                    id: project.id,
                    name: project.name,
                    createdAt: project.createdAt,
                    updatedAt: Date(),
                    audioAsset: project.audioAsset,
                    waveformPeaks: self.makeWaveformPeaks(for: asset.id),
                    setup: project.setup,
                    cues: project.cues,
                    people: project.people,
                    labels: project.labels
                )
            }
        }()
        _ = try await (assetWrite, peaksWrite)
    }
}
