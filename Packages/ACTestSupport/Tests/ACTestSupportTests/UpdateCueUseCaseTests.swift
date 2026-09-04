import ACCore
@testable import ACTestSupport
import XCTest

/// Exercises `UpdateCueUseCase`'s edit/split/merge paths (`ROADMAP.md` D9,
/// pulled forward from D10/T10.1 — see `docs/DECISIONS.md`) against the real
/// `InMemoryProjectRepository` fake, per `CONTRIBUTING.md` §5.
final class UpdateCueUseCaseTests: XCTestCase {
    private static func makeProject(cues: [Cue]) -> Project {
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

    private static func makeCue(
        title: String = "Detected Cue",
        duration: Double = 30,
        source: CueSource = .detectedFromAudio,
        startSeconds: Double? = 10,
        rightHolders: [CueRightHolder] = [],
        workNumber: String? = nil,
        notes: String? = nil,
        isArrangementOfProtectedOriginal: Bool = false
    ) -> Cue {
        Cue(
            title: title,
            workNumber: workNumber,
            duration: MediaDuration(seconds: duration),
            rightHolders: rightHolders,
            isArrangementOfProtectedOriginal: isArrangementOfProtectedOriginal,
            source: source,
            startTimecode: startSeconds.map { Timecode(offsetSeconds: $0) },
            notes: notes
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

    func test_split_earlierHalfKeepsIDAndNonPositionFields_laterHalfIsFreshWithAddCueDefaults() async throws {
        let rightHolder = CueRightHolder(
            party: .person(UUID()),
            role: .composer,
            performanceBroadcastShare: 100,
            mechanicalRightsShare: 100
        )
        let cue = Self.makeCue(
            title: "Original",
            duration: 60,
            startSeconds: 100,
            rightHolders: [rightHolder],
            workNumber: "W1",
            notes: "note",
            isArrangementOfProtectedOriginal: true
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

        XCTAssertNotEqual(second.id, cue.id)
        XCTAssertEqual(second.title, "")
        XCTAssertNil(second.workNumber)
        XCTAssertNil(second.notes)
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

    func test_merge_appliesEveryFieldRuleExactly() async throws {
        let rightHolderA = CueRightHolder(
            party: .person(UUID()),
            role: .composer,
            performanceBroadcastShare: 100,
            mechanicalRightsShare: 100
        )
        let rightHolderB = CueRightHolder(
            party: .person(UUID()),
            role: .composer,
            performanceBroadcastShare: 100,
            mechanicalRightsShare: 100
        )
        let preceding = Self.makeCue(
            title: "First Half",
            duration: 30,
            startSeconds: 100,
            rightHolders: [rightHolderA],
            workNumber: "W1",
            notes: nil,
            isArrangementOfProtectedOriginal: false
        )
        let following = Self.makeCue(
            title: "",
            duration: 30,
            startSeconds: 130,
            rightHolders: [rightHolderA, rightHolderB],
            workNumber: nil,
            notes: "second note",
            isArrangementOfProtectedOriginal: true
        )
        let project = Self.makeProject(cues: [preceding, following])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = UpdateCueUseCase(projectRepository: repository)

        let merged = try await useCase.merge(
            projectID: project.id,
            precedingCueID: preceding.id,
            cueID: following.id
        )

        XCTAssertEqual(merged.id, preceding.id)
        XCTAssertEqual(merged.startTimecode, Timecode(offsetSeconds: 100))
        XCTAssertEqual(merged.duration, MediaDuration(seconds: 60))
        XCTAssertEqual(merged.title, "First Half") // earlier non-empty wins
        XCTAssertEqual(merged.workNumber, "W1") // earlier non-nil wins
        XCTAssertEqual(merged.notes, "second note") // earlier nil -> later wins
        XCTAssertTrue(merged.isArrangementOfProtectedOriginal) // logical OR
        XCTAssertEqual(merged.rightHolders, [rightHolderA, rightHolderA, rightHolderB]) // concatenation, no dedup
        XCTAssertEqual(merged.source, .manual)

        let updated = try await repository.fetch(id: project.id)
        XCTAssertEqual(updated?.cues.map(\.id), [preceding.id])
    }

    func test_merge_nonContiguous_throwsAndDoesNotMutate() async throws {
        let preceding = Self.makeCue(duration: 30, startSeconds: 100)
        // A real gap: `following` starts a full second after `preceding` ends (130),
        // far outside the 0.001s merge epsilon.
        let following = Self.makeCue(duration: 30, startSeconds: 131)
        let project = Self.makeProject(cues: [preceding, following])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = UpdateCueUseCase(projectRepository: repository)

        do {
            _ = try await useCase.merge(projectID: project.id, precedingCueID: preceding.id, cueID: following.id)
            XCTFail("Expected mergeNotContiguous")
        } catch UpdateCueUseCaseError.mergeNotContiguous {}

        let unchanged = try await repository.fetch(id: project.id)
        XCTAssertEqual(unchanged?.cues.count, 2)
    }

    func test_merge_toleranceIsStricterThanEmbeddedMarkerMergeTolerance() async throws {
        // 0.5s gap: well inside AnalysisSettings' default 1.0s
        // embeddedMarkerMergeToleranceSeconds, but far outside merge's own
        // deliberately much stricter 0.001s epsilon (SPEC.md §4.15).
        let preceding = Self.makeCue(duration: 30, startSeconds: 100)
        let following = Self.makeCue(duration: 30, startSeconds: 130.5)
        let project = Self.makeProject(cues: [preceding, following])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = UpdateCueUseCase(projectRepository: repository)

        do {
            _ = try await useCase.merge(projectID: project.id, precedingCueID: preceding.id, cueID: following.id)
            XCTFail("Expected mergeNotContiguous")
        } catch UpdateCueUseCaseError.mergeNotContiguous {}
    }
}
