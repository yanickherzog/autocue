import ACCore
@testable import ACTestSupport
import XCTest

/// `UpdateCueUseCase.moveBoundary` (SPEC.md §4.19, "Boundary markers:
/// contiguous vs. non-contiguous") against the real `InMemoryProjectRepository`
/// fake, per `CONTRIBUTING.md` §5 — split into its own file/class from
/// `UpdateCueUseCaseTests` purely to stay under this project's
/// type-body-length lint limit, the same reason `UpdateCueUseCase` itself
/// splits `moveBoundary` into `UpdateCueUseCase+MoveBoundary.swift`.
final class UpdateCueUseCaseMoveBoundaryTests: XCTestCase {
    /// Not `private`: `UpdateCueUseCaseMoveBoundaryTests+EdgeCases.swift`
    /// (split into its own file purely to stay under this project's
    /// type-body-length lint limit) needs these three helpers too.
    static func makeProject(cues: [Cue], audioAsset: AudioAsset? = nil) -> Project {
        Project(
            name: "Reel One",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            audioAsset: audioAsset,
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

    static func makeAudioAsset(durationSeconds: Double) -> AudioAsset {
        AudioAsset(
            originalFileName: "reel-one.wav",
            securityScopedBookmark: Data(),
            duration: MediaDuration(seconds: durationSeconds),
            sampleRate: 48000,
            channelCount: 2,
            bitDepth: 24,
            importedAt: Date(timeIntervalSince1970: 0)
        )
    }

    static func makeCue(
        title: String = "Detected Cue",
        duration: Double = 30,
        source: CueSource = .detectedFromAudio,
        startSeconds: Double? = 10
    ) -> Cue {
        Cue(
            title: title,
            duration: MediaDuration(seconds: duration),
            rightHolders: [],
            source: source,
            startTimecode: startSeconds.map { Timecode(offsetSeconds: $0) }
        )
    }

    func test_moveBoundary_nonContiguous_endMarkerMovesWithoutTouchingFollowingCue() async throws {
        let preceding = Self.makeCue(duration: 30, startSeconds: 100) // end 130
        let following = Self.makeCue(duration: 20, startSeconds: 140) // gap of 10s
        let project = Self.makeProject(cues: [preceding, following])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = UpdateCueUseCase(projectRepository: repository)

        let result = try await useCase.moveBoundary(
            projectID: project.id,
            marker: .end(preceding.id),
            toOffsetSeconds: 125
        )

        XCTAssertEqual(Set(result.updatedCues.map(\.id)), [preceding.id])
        let updatedProject = try await repository.fetch(id: project.id)
        let updated = try XCTUnwrap(updatedProject)
        let updatedPreceding = try XCTUnwrap(updated.cues.first { $0.id == preceding.id })
        XCTAssertEqual(updatedPreceding.duration, MediaDuration(seconds: 25))
        XCTAssertEqual(updatedPreceding.source, .manual)
        let unchangedFollowing = try XCTUnwrap(updated.cues.first { $0.id == following.id })
        XCTAssertEqual(unchangedFollowing.startTimecode, Timecode(offsetSeconds: 140))
        XCTAssertEqual(unchangedFollowing.duration, MediaDuration(seconds: 20))
        XCTAssertEqual(unchangedFollowing.source, following.source) // never touched, never reclassified
    }

    func test_moveBoundary_nonContiguous_startMarkerMovesWithoutTouchingPrecedingCue() async throws {
        let preceding = Self.makeCue(duration: 30, startSeconds: 100) // end 130
        let following = Self.makeCue(duration: 20, startSeconds: 140) // gap of 10s, own end 160
        let project = Self.makeProject(cues: [preceding, following])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = UpdateCueUseCase(projectRepository: repository)

        let result = try await useCase.moveBoundary(
            projectID: project.id,
            marker: .start(following.id),
            toOffsetSeconds: 135
        )

        XCTAssertEqual(Set(result.updatedCues.map(\.id)), [following.id])
        let updatedProject = try await repository.fetch(id: project.id)
        let updated = try XCTUnwrap(updatedProject)
        let updatedFollowing = try XCTUnwrap(updated.cues.first { $0.id == following.id })
        XCTAssertEqual(updatedFollowing.startTimecode, Timecode(offsetSeconds: 135))
        XCTAssertEqual(updatedFollowing.duration, MediaDuration(seconds: 25)) // own end (160) held fixed
        let unchangedPreceding = try XCTUnwrap(updated.cues.first { $0.id == preceding.id })
        XCTAssertEqual(unchangedPreceding.startTimecode, Timecode(offsetSeconds: 100))
        XCTAssertEqual(unchangedPreceding.duration, MediaDuration(seconds: 30))
    }

    private struct Fixture {
        let projectID: Project.ID
        let preceding: Cue
        let following: Cue
        let useCase: UpdateCueUseCase
        let repository: InMemoryProjectRepository
    }

    private static func freshFixture() -> Fixture {
        let preceding = Self.makeCue(duration: 30, startSeconds: 100) // end 130
        let following = Self.makeCue(duration: 20, startSeconds: 140) // gap of 10s
        let project = Self.makeProject(cues: [preceding, following])
        let repository = InMemoryProjectRepository(projects: [project])
        return Fixture(
            projectID: project.id,
            preceding: preceding,
            following: following,
            useCase: UpdateCueUseCase(projectRepository: repository),
            repository: repository
        )
    }

    func test_moveBoundary_nonContiguous_towardNeighbor_clampsAtZeroGapRegardlessOfHowFarRequested() async throws {
        // Requesting exactly the neighbor's position...
        let fixtureA = Self.freshFixture()
        _ = try await fixtureA.useCase.moveBoundary(
            projectID: fixtureA.projectID,
            marker: .end(fixtureA.preceding.id),
            toOffsetSeconds: 140
        )
        let projectAOrNil = try await fixtureA.repository.fetch(id: fixtureA.projectID)
        let projectA = try XCTUnwrap(projectAOrNil)
        let updatedPrecedingA = try XCTUnwrap(projectA.cues.first { $0.id == fixtureA.preceding.id })

        // ...and requesting far past it, from the same starting (non-contiguous) state...
        let fixtureB = Self.freshFixture()
        _ = try await fixtureB.useCase.moveBoundary(
            projectID: fixtureB.projectID,
            marker: .end(fixtureB.preceding.id),
            toOffsetSeconds: 5000
        )
        let projectBOrNil = try await fixtureB.repository.fetch(id: fixtureB.projectID)
        let projectB = try XCTUnwrap(projectBOrNil)
        let updatedPrecedingB = try XCTUnwrap(projectB.cues.first { $0.id == fixtureB.preceding.id })

        // ...both produce the identical clamped result: touching, never crossing.
        XCTAssertEqual(updatedPrecedingA.duration, MediaDuration(seconds: 40))
        XCTAssertEqual(updatedPrecedingB.duration, MediaDuration(seconds: 40))

        // Clamping to zero gap alone never merges the two cues.
        XCTAssertEqual(projectA.cues.count, 2)
        XCTAssertEqual(Set(projectA.cues.map(\.id)), [fixtureA.preceding.id, fixtureA.following.id])
        XCTAssertEqual(projectB.cues.count, 2)
        XCTAssertEqual(Set(projectB.cues.map(\.id)), [fixtureB.preceding.id, fixtureB.following.id])
    }

    func test_moveBoundary_contiguous_pushThrough_atomicTwoCueWrite() async throws {
        let preceding = Self.makeCue(duration: 30, startSeconds: 100) // end 130
        let following = Self.makeCue(duration: 20, startSeconds: 130) // touching, own end 150
        let project = Self.makeProject(cues: [preceding, following])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = UpdateCueUseCase(projectRepository: repository)

        let result = try await useCase.moveBoundary(
            projectID: project.id,
            marker: .end(preceding.id),
            toOffsetSeconds: 145
        )

        XCTAssertEqual(Set(result.updatedCues.map(\.id)), [preceding.id, following.id])
        let updatedProject = try await repository.fetch(id: project.id)
        let updated = try XCTUnwrap(updatedProject)
        let updatedPreceding = try XCTUnwrap(updated.cues.first { $0.id == preceding.id })
        let updatedFollowing = try XCTUnwrap(updated.cues.first { $0.id == following.id })
        XCTAssertEqual(updatedPreceding.duration, MediaDuration(seconds: 45)) // end now 145
        XCTAssertEqual(updatedFollowing.startTimecode, Timecode(offsetSeconds: 145))
        XCTAssertEqual(updatedFollowing.duration, MediaDuration(seconds: 5)) // own end (150) held fixed
        XCTAssertEqual(updatedPreceding.source, .manual)
        XCTAssertEqual(updatedFollowing.source, .manual)
    }

    func test_moveBoundary_pushThrough_clampsAtSuccessorsOwnFarEnd_neverCascadesToThirdCue() async throws {
        let first = Self.makeCue(duration: 30, startSeconds: 100) // end 130
        let middle = Self.makeCue(duration: 20, startSeconds: 130) // touching `first`, own end 150
        let third = Self.makeCue(duration: 15, startSeconds: 150) // touching `middle`
        let project = Self.makeProject(cues: [first, middle, third])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = UpdateCueUseCase(projectRepository: repository)

        let result = try await useCase.moveBoundary(
            projectID: project.id,
            marker: .end(first.id),
            toOffsetSeconds: 500 // far past every cue in the project
        )

        XCTAssertEqual(Set(result.updatedCues.map(\.id)), [first.id, middle.id]) // third never written
        let updatedProject = try await repository.fetch(id: project.id)
        let updated = try XCTUnwrap(updatedProject)
        let updatedFirst = try XCTUnwrap(updated.cues.first { $0.id == first.id })
        let updatedMiddle = try XCTUnwrap(updated.cues.first { $0.id == middle.id })
        let unchangedThird = try XCTUnwrap(updated.cues.first { $0.id == third.id })
        XCTAssertEqual(updatedFirst.duration, MediaDuration(seconds: 50)) // clamped at middle's own far end (150)
        XCTAssertEqual(updatedMiddle.startTimecode, Timecode(offsetSeconds: 150))
        XCTAssertEqual(updatedMiddle.duration, .zero) // collapsed, but never pushed further
        XCTAssertEqual(unchangedThird.startTimecode, Timecode(offsetSeconds: 150)) // byte-for-byte unchanged
        XCTAssertEqual(unchangedThird.duration, MediaDuration(seconds: 15))
    }

    func test_moveBoundary_pullingContiguousBoundaryApart_convertsToNonContiguousSingleCueWrite() async throws {
        let preceding = Self.makeCue(duration: 30, startSeconds: 100) // end 130
        let following = Self.makeCue(duration: 20, startSeconds: 130) // touching
        let project = Self.makeProject(cues: [preceding, following])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = UpdateCueUseCase(projectRepository: repository)

        let result = try await useCase.moveBoundary(
            projectID: project.id,
            marker: .end(preceding.id),
            toOffsetSeconds: 120 // away from following, opening a gap
        )

        XCTAssertEqual(Set(result.updatedCues.map(\.id)), [preceding.id]) // single-cue write only
        let updatedProject = try await repository.fetch(id: project.id)
        let updated = try XCTUnwrap(updatedProject)
        let updatedPreceding = try XCTUnwrap(updated.cues.first { $0.id == preceding.id })
        let unchangedFollowing = try XCTUnwrap(updated.cues.first { $0.id == following.id })
        XCTAssertEqual(updatedPreceding.duration, MediaDuration(seconds: 20)) // end now 120
        XCTAssertEqual(unchangedFollowing.startTimecode, Timecode(offsetSeconds: 130)) // untouched
        XCTAssertEqual(unchangedFollowing.duration, MediaDuration(seconds: 20))
        // A real, non-zero gap now exists: 130 - 120 = 10s.
    }

    func test_moveBoundary_pullingApartABoundarySplitJustCreated_behavesLikeAnyOtherContiguousBoundary() async throws {
        let cue = Self.makeCue(title: "Original", duration: 60, startSeconds: 100) // end 160
        let project = Self.makeProject(cues: [cue])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = UpdateCueUseCase(projectRepository: repository)

        let (first, second) = try await useCase.split(projectID: project.id, cueID: cue.id, atOffsetSeconds: 130)

        let result = try await useCase.moveBoundary(
            projectID: project.id,
            marker: .end(first.id),
            toOffsetSeconds: 110 // pull the freshly-split boundary apart
        )

        XCTAssertEqual(Set(result.updatedCues.map(\.id)), [first.id]) // no special-cased "just split" state
        let updatedProject = try await repository.fetch(id: project.id)
        let updated = try XCTUnwrap(updatedProject)
        let updatedFirst = try XCTUnwrap(updated.cues.first { $0.id == first.id })
        let unchangedSecond = try XCTUnwrap(updated.cues.first { $0.id == second.id })
        XCTAssertEqual(updatedFirst.duration, MediaDuration(seconds: 10)) // end now 110
        XCTAssertEqual(
            unchangedSecond.startTimecode,
            Timecode(offsetSeconds: 130)
        ) // exactly split's own result, untouched
        XCTAssertEqual(unchangedSecond.duration, MediaDuration(seconds: 30))
    }
}
