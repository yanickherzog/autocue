import ACCore
@testable import ACTestSupport
import XCTest

/// `merge` (`UpdateCueUseCase`, SPEC.md §4.19) — split into its own
/// file/extension purely to keep `UpdateCueUseCaseTests` under this
/// project's type-body-length lint limit, the same reason
/// `UpdateCueUseCaseTests+Delete.swift` already is. Reuses that class's
/// `makeProject`/`makeCue` helpers, made non-`private` there specifically so
/// this file can share them.
extension UpdateCueUseCaseTests {
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

    /// Regression: `merge`'s result must carry a recording label forward
    /// (preceding wins, same "prefer earlier" rule as `workNumber`), not
    /// silently drop it (SPEC.md §4.26, `docs/DECISIONS.md`).
    func test_merge_preservesRecordingLabel_precedingWins() async throws {
        let recordingLabelID = UUID()
        let preceding = Self.makeCue(startSeconds: 100, recordingLabel: .label(recordingLabelID))
        let following = Self.makeCue(startSeconds: 130)
        let project = Self.makeProject(cues: [preceding, following])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = UpdateCueUseCase(projectRepository: repository)

        let merged = try await useCase.merge(
            projectID: project.id,
            precedingCueID: preceding.id,
            cueID: following.id
        )

        XCTAssertEqual(merged.recordingLabel, .label(recordingLabelID))
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
