import ACCore
@testable import ACTestSupport
import XCTest

/// Exercises `UpdateCueUseCase`'s edit/split/merge paths (`ROADMAP.md` D9,
/// pulled forward from D10/T10.1 — see `docs/DECISIONS.md`) against the real
/// `InMemoryProjectRepository` fake, per `CONTRIBUTING.md` §5.
final class UpdateCueUseCaseTests: XCTestCase {
    /// Not `private`: `UpdateCueUseCaseTests+Delete.swift` needs these too —
    /// split into its own file purely to stay under this project's
    /// type-body-length lint limit, same reason
    /// `UpdateCueUseCaseMoveBoundaryTests+EdgeCases.swift` already is.
    static func makeProject(cues: [Cue]) -> Project {
        Project(
            name: "Reel One",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            setup: Setup(
                title: "A Swiss Story",
                productionRuntime: .zero,
                totalMusicRuntime: .zero,
                productionYear: 2026,
                containsAdditionalUndeclaredWorks: .no,
                productionTypes: [.documentaryFilm],
                declarationDate: Date(timeIntervalSince1970: 0)
            ),
            cues: cues
        )
    }

    static func makeCue(
        title: String = "Detected Cue",
        duration: Double = 30,
        source: CueSource = .detectedFromAudio,
        startSeconds: Double? = 10,
        rightHolders: [CueRightHolder] = [],
        workNumber: String? = nil,
        notes: String? = nil,
        isArrangementOfProtectedOriginal: Bool = false,
        recordingLabel: Party? = nil
    ) -> Cue {
        Cue(
            title: title,
            workNumber: workNumber,
            duration: MediaDuration(seconds: duration),
            rightHolders: rightHolders,
            isArrangementOfProtectedOriginal: isArrangementOfProtectedOriginal,
            source: source,
            startTimecode: startSeconds.map { Timecode(offsetSeconds: $0) },
            notes: notes,
            recordingLabel: recordingLabel
        )
    }

    // MARK: - Edit

    func test_edit_reclassifiesToManualRegardlessOfPriorSourceOrFieldChanged() async throws {
        let cue = Self.makeCue(source: .detectedFromAudio)
        let project = Self.makeProject(cues: [cue])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = UpdateCueUseCase(projectRepository: repository)

        let edited = try await useCase.edit(projectID: project.id, cueID: cue.id) { existing in
            Cue(
                id: existing.id,
                title: "Renamed",
                workNumber: existing.workNumber,
                duration: existing.duration,
                rightHolders: existing.rightHolders,
                isArrangementOfProtectedOriginal: existing.isArrangementOfProtectedOriginal,
                source: existing.source,
                startTimecode: existing.startTimecode,
                notes: existing.notes
            )
        }

        XCTAssertEqual(edited.title, "Renamed")
        XCTAssertEqual(edited.source, .manual)
    }

    func test_edit_recomputesTotalMusicRuntime() async throws {
        let cue = Self.makeCue(duration: 30)
        let project = Self.makeProject(cues: [cue])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = UpdateCueUseCase(projectRepository: repository)

        _ = try await useCase.edit(projectID: project.id, cueID: cue.id) { existing in
            Cue(
                id: existing.id,
                title: existing.title,
                workNumber: existing.workNumber,
                duration: MediaDuration(seconds: 45),
                rightHolders: existing.rightHolders,
                isArrangementOfProtectedOriginal: existing.isArrangementOfProtectedOriginal,
                source: existing.source,
                startTimecode: existing.startTimecode,
                notes: existing.notes
            )
        }

        let updated = try await repository.fetch(id: project.id)
        XCTAssertEqual(updated?.setup.totalMusicRuntime, MediaDuration(seconds: 45))
    }

    /// **Regression test for a real bug found while building the Cues tab's
    /// Recording Info UI (SPEC.md §4.26, `docs/DECISIONS.md`):**
    /// `reclassifiedAsManual()` — called by every `edit()` write, on
    /// whatever `Cue` `transform` returns — reconstructed that `Cue` without
    /// carrying `recordingLabel`/`.recordingLabelNumber`/`.recordingISRC`
    /// forward, silently wiping all three on every single `edit()` call
    /// regardless of what the transform itself did or didn't touch. Proven
    /// here with an identity transform (`{ $0 }`) specifically, so this
    /// exercises `reclassifiedAsManual()` in isolation — every real
    /// production transform closure (`saveTitle`, `saveStartTimecode`,
    /// `commitRightHolderEdits`, the new `+RecordingInfo.swift` methods) was
    /// separately audited and fixed to forward these three fields from its
    /// own `existing`/`cue` parameter too, since `reclassifiedAsManual()`
    /// can only preserve what `transform` actually returned to it.
    func test_edit_identityTransform_stillPreservesRecordingInfoFields() async throws {
        let labelID = UUID()
        var cue = Self.makeCue()
        cue = Cue(
            id: cue.id,
            title: cue.title,
            duration: cue.duration,
            rightHolders: cue.rightHolders,
            source: cue.source,
            startTimecode: cue.startTimecode,
            recordingLabel: .label(labelID),
            recordingLabelNumber: "NDR-4471",
            recordingISRC: "CH-A12-26-00001"
        )
        let project = Self.makeProject(cues: [cue])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = UpdateCueUseCase(projectRepository: repository)

        let edited = try await useCase.edit(projectID: project.id, cueID: cue.id) { $0 }

        XCTAssertEqual(edited.recordingLabel, .label(labelID))
        XCTAssertEqual(edited.recordingLabelNumber, "NDR-4471")
        XCTAssertEqual(edited.recordingISRC, "CH-A12-26-00001")
    }

    func test_edit_unknownCueID_throwsCueNotFound() async throws {
        let project = Self.makeProject(cues: [])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = UpdateCueUseCase(projectRepository: repository)
        let unknownID = UUID()

        do {
            _ = try await useCase.edit(projectID: project.id, cueID: unknownID) { $0 }
            XCTFail("Expected cueNotFound")
        } catch UpdateCueUseCaseError.cueNotFound(unknownID) {}
    }

    // MARK: - Split

    func test_split_earlierHalfKeepsIDAndNonPositionFields_laterHalfIsFreshWithAutoPopulatedDefaults() async throws {
        let rightHolder = CueRightHolder(
            party: .person(UUID()),
            role: .composer,
            performanceBroadcastShare: 100,
            mechanicalRightsShare: 100
        )
        let recordingLabelID = UUID()
        let cue = Self.makeCue(
            title: "Original",
            duration: 60,
            startSeconds: 100,
            rightHolders: [rightHolder],
            workNumber: "W1",
            notes: "note",
            isArrangementOfProtectedOriginal: true,
            recordingLabel: .label(recordingLabelID)
        )
        let project = Self.makeProject(cues: [cue])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = UpdateCueUseCase(projectRepository: repository)

        let (first, second) = try await useCase.split(projectID: project.id, cueID: cue.id, atOffsetSeconds: 130)

        XCTAssertEqual(first.id, cue.id)
        XCTAssertEqual(first.title, "Original")
        XCTAssertEqual(first.workNumber, "W1")
        XCTAssertEqual(first.notes, "note")
        XCTAssertEqual(first.rightHolders, [rightHolder])
        XCTAssertTrue(first.isArrangementOfProtectedOriginal)
        XCTAssertEqual(first.startTimecode, Timecode(offsetSeconds: 100))
        XCTAssertEqual(first.duration, MediaDuration(seconds: 30))
        XCTAssertEqual(first.source, .manual)
        // Regression: `split`'s earlier half must carry the original cue's
        // recording info forward (SPEC.md §4.26) — a real bug found while
        // building the Cues tab's Recording Info UI, fixed directly in
        // `split`'s own `earlier` construction.
        XCTAssertEqual(first.recordingLabel, .label(recordingLabelID))

        XCTAssertNotEqual(second.id, cue.id)
        // "ProjectTitle_Score_Cue-N" (ROADMAP.md D10) -- a real, persisted
        // default (not an empty title), using the later half's own final
        // 1-indexed position (2nd of 2 cues after the split).
        XCTAssertEqual(second.title, "A Swiss Story_Score_Cue-2")
        XCTAssertNil(second.workNumber)
        XCTAssertNil(second.notes)
        // Empty here because `Self.makeProject`'s fixture has no `people` at
        // all -- CueAutoPopulation.defaultRightHolders(people:) correctly
        // yields [] when there's no composer/arranger roster to draw from,
        // not because right-holder auto-population doesn't apply to split.
        XCTAssertTrue(second.rightHolders.isEmpty)
        XCTAssertFalse(second.isArrangementOfProtectedOriginal)
        XCTAssertEqual(second.startTimecode, Timecode(offsetSeconds: 130))
        XCTAssertEqual(second.duration, MediaDuration(seconds: 30))
        XCTAssertEqual(second.source, .manual)

        let updated = try await repository.fetch(id: project.id)
        XCTAssertEqual(updated?.cues.map(\.id), [first.id, second.id])
    }

    func test_split_reconstructsOriginalSpanExactly_noGapNoOverlap() async throws {
        let cue = Self.makeCue(duration: 60, startSeconds: 100)
        let project = Self.makeProject(cues: [cue])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = UpdateCueUseCase(projectRepository: repository)

        let (first, second) = try await useCase.split(projectID: project.id, cueID: cue.id, atOffsetSeconds: 140)

        let firstEnd = try XCTUnwrap(first.startTimecode?.offsetSeconds) + first.duration.seconds
        XCTAssertEqual(firstEnd, try XCTUnwrap(second.startTimecode?.offsetSeconds), accuracy: 0.0001)
        let secondEnd = try XCTUnwrap(second.startTimecode?.offsetSeconds) + second.duration.seconds
        let originalEnd = try XCTUnwrap(cue.startTimecode?.offsetSeconds) + cue.duration.seconds
        XCTAssertEqual(secondEnd, originalEnd, accuracy: 0.0001)
    }

    func test_split_withinEpsilonOfEitherEndpoint_throws() async throws {
        let cue = Self.makeCue(duration: 60, startSeconds: 100)
        let project = Self.makeProject(cues: [cue])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = UpdateCueUseCase(projectRepository: repository)

        do {
            _ = try await useCase.split(projectID: project.id, cueID: cue.id, atOffsetSeconds: 100.0001)
            XCTFail("Expected splitOffsetTooCloseToEndpoint")
        } catch UpdateCueUseCaseError.splitOffsetTooCloseToEndpoint {}

        do {
            _ = try await useCase.split(projectID: project.id, cueID: cue.id, atOffsetSeconds: 159.9999)
            XCTFail("Expected splitOffsetTooCloseToEndpoint")
        } catch UpdateCueUseCaseError.splitOffsetTooCloseToEndpoint {}
    }

    // MARK: - Merge

    // See `UpdateCueUseCaseTests+Merge.swift` — moved out of this file to
    // keep it under this project's type-body-length lint limit.
}
