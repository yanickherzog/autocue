import ACCore
@testable import ACTestSupport
import XCTest

/// The permanently-neighborless first/last-cue cases, plus the "touching
/// alone never merges" guarantee — split into its own file/extension purely
/// to keep `UpdateCueUseCaseMoveBoundaryTests` under this project's
/// type-body-length lint limit, the same reason `UpdateCueUseCase` itself
/// splits `moveBoundary` into `UpdateCueUseCase+MoveBoundary.swift`. Reuses
/// that class's `makeProject`/`makeCue`/`makeAudioAsset` helpers, made
/// non-`private` there specifically so this file can share them.
extension UpdateCueUseCaseMoveBoundaryTests {
    func test_moveBoundary_firstCueStart_hasNoPredecessor_singleCueWriteBothDirections() async throws {
        let first = Self.makeCue(duration: 30, startSeconds: 100) // end 130 — the file's very first cue
        let following = Self.makeCue(duration: 20, startSeconds: 140)
        let project = Self.makeProject(cues: [first, following])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = UpdateCueUseCase(projectRepository: repository)

        _ = try await useCase.moveBoundary(projectID: project.id, marker: .start(first.id), toOffsetSeconds: 50)
        var updatedOrNil = try await repository.fetch(id: project.id)
        var updated = try XCTUnwrap(updatedOrNil)
        var updatedFirst = try XCTUnwrap(updated.cues.first { $0.id == first.id })
        XCTAssertEqual(updatedFirst.startTimecode, Timecode(offsetSeconds: 50))
        XCTAssertEqual(updatedFirst.duration, MediaDuration(seconds: 80)) // own end (130) held fixed

        // Requesting a negative offset — clamped at the file's own start (0), never crashes or goes negative.
        _ = try await useCase.moveBoundary(projectID: project.id, marker: .start(first.id), toOffsetSeconds: -20)
        updatedOrNil = try await repository.fetch(id: project.id)
        updated = try XCTUnwrap(updatedOrNil)
        updatedFirst = try XCTUnwrap(updated.cues.first { $0.id == first.id })
        XCTAssertEqual(updatedFirst.startTimecode, Timecode(offsetSeconds: 0))
        XCTAssertEqual(updatedFirst.duration, MediaDuration(seconds: 130))

        // Neither direction ever touched `following` — there is no neighbor on this side to couple to.
        let unchangedFollowing = try XCTUnwrap(updated.cues.first { $0.id == following.id })
        XCTAssertEqual(unchangedFollowing.startTimecode, Timecode(offsetSeconds: 140))
        XCTAssertEqual(unchangedFollowing.duration, MediaDuration(seconds: 20))
    }

    func test_moveBoundary_lastCueEnd_hasNoSuccessor_singleCueWriteBoundedByFileDurationWhenKnown() async throws {
        let preceding = Self.makeCue(duration: 20, startSeconds: 50)
        let last = Self.makeCue(duration: 30, startSeconds: 100) // end 130 — the file's very last cue
        let project = Self.makeProject(cues: [preceding, last], audioAsset: Self.makeAudioAsset(durationSeconds: 200))
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = UpdateCueUseCase(projectRepository: repository)

        _ = try await useCase.moveBoundary(projectID: project.id, marker: .end(last.id), toOffsetSeconds: 500)
        let updatedProject = try await repository.fetch(id: project.id)
        let updated = try XCTUnwrap(updatedProject)
        let updatedLast = try XCTUnwrap(updated.cues.first { $0.id == last.id })
        XCTAssertEqual(updatedLast.duration, MediaDuration(seconds: 100)) // clamped at the file's own duration (200)

        let unchangedPreceding = try XCTUnwrap(updated.cues.first { $0.id == preceding.id })
        XCTAssertEqual(unchangedPreceding.startTimecode, Timecode(offsetSeconds: 50))
        XCTAssertEqual(unchangedPreceding.duration, MediaDuration(seconds: 20)) // no neighbor on this side either
    }

    func test_moveBoundary_touchingZeroGapAloneNeverMerges_mergeIsStillTheOnlyWayToCombine() async throws {
        let preceding = Self.makeCue(duration: 30, startSeconds: 100) // end 130
        let following = Self.makeCue(duration: 20, startSeconds: 140) // gap of 10s
        let project = Self.makeProject(cues: [preceding, following])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = UpdateCueUseCase(projectRepository: repository)

        _ = try await useCase.moveBoundary(projectID: project.id, marker: .end(preceding.id), toOffsetSeconds: 140)
        let touchingOrNil = try await repository.fetch(id: project.id)
        let touching = try XCTUnwrap(touchingOrNil)
        XCTAssertEqual(touching.cues.count, 2) // clamped to exactly touching, not combined

        let merged = try await useCase.merge(projectID: project.id, precedingCueID: preceding.id, cueID: following.id)
        XCTAssertEqual(merged.id, preceding.id)
        let afterMergeOrNil = try await repository.fetch(id: project.id)
        let afterMerge = try XCTUnwrap(afterMergeOrNil)
        XCTAssertEqual(afterMerge.cues.count, 1) // only the explicit merge gesture actually combines them
    }
}
