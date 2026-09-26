import ACCore
@testable import ACTestSupport
import XCTest

/// `UpdateCueUseCase.copyRightHolders`/`.restoreRightHolders` (`ROADMAP.md`
/// D10, "Copy Split to Other Cues") — split into its own file mirroring the
/// production split (`+RightHolders.swift`).
final class UpdateCueUseCaseRightHoldersTests: XCTestCase {
    func test_copyRightHolders_writesTheSameListOntoEveryCue_includingTheSource() async throws {
        let sourceRightHolder = CueRightHolder(
            party: .person(UUID()), role: .composer, performanceBroadcastShare: 100, mechanicalRightsShare: 100
        )
        let source = UpdateCueUseCaseTests.makeCue(title: "Source", rightHolders: [sourceRightHolder])
        let other1 = UpdateCueUseCaseTests.makeCue(title: "Other 1", source: .manual, startSeconds: 200)
        let other2 = UpdateCueUseCaseTests.makeCue(title: "Other 2", source: .embeddedMarker, startSeconds: 300)
        let project = UpdateCueUseCaseTests.makeProject(cues: [source, other1, other2])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = UpdateCueUseCase(projectRepository: repository)

        let newSplit = [
            CueRightHolder(
                party: .person(UUID()), role: .arranger, performanceBroadcastShare: 100, mechanicalRightsShare: 100
            ),
        ]
        let updatedCues = try await useCase.copyRightHolders(projectID: project.id, rightHolders: newSplit)

        XCTAssertEqual(updatedCues.count, 3)
        for cue in updatedCues {
            XCTAssertEqual(cue.rightHolders, newSplit)
            XCTAssertEqual(cue.source, .manual)
        }
        // Every other field on the untouched cues is preserved exactly.
        let persistedOther1 = try XCTUnwrap(updatedCues.first { $0.id == other1.id })
        XCTAssertEqual(persistedOther1.title, "Other 1")
        XCTAssertEqual(persistedOther1.startTimecode, other1.startTimecode)
    }

    func test_restoreRightHolders_bringsEveryCueBackToItsExactPriorList() async throws {
        let rightHolderA = CueRightHolder(
            party: .person(UUID()), role: .composer, performanceBroadcastShare: 100, mechanicalRightsShare: 100
        )
        let rightHolderB = CueRightHolder(
            party: .person(UUID()), role: .arranger, performanceBroadcastShare: 60, mechanicalRightsShare: 60
        )
        let cueA = UpdateCueUseCaseTests.makeCue(title: "A", rightHolders: [rightHolderA])
        let cueB = UpdateCueUseCaseTests.makeCue(title: "B", startSeconds: 200, rightHolders: [rightHolderB])
        let project = UpdateCueUseCaseTests.makeProject(cues: [cueA, cueB])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = UpdateCueUseCase(projectRepository: repository)

        let snapshot: [Cue.ID: [CueRightHolder]] = [cueA.id: [rightHolderA], cueB.id: [rightHolderB]]

        // Overwrite both with a third, unrelated split first (the forward
        // "copy" a restore would be undoing).
        _ = try await useCase.copyRightHolders(
            projectID: project.id,
            rightHolders: [
                CueRightHolder(
                    party: .person(UUID()), role: .publisher,
                    performanceBroadcastShare: 100, mechanicalRightsShare: 100
                ),
            ]
        )

        let restored = try await useCase.restoreRightHolders(projectID: project.id, snapshot: snapshot)

        let restoredA = try XCTUnwrap(restored.first { $0.id == cueA.id })
        let restoredB = try XCTUnwrap(restored.first { $0.id == cueB.id })
        XCTAssertEqual(restoredA.rightHolders, [rightHolderA])
        XCTAssertEqual(restoredB.rightHolders, [rightHolderB])
    }

    /// The exact scenario requested: copy onto every cue, then restore from
    /// the pre-copy snapshot, confirming every cue's original right-holder
    /// data is fully restored — not partially, and not just the one the
    /// sheet was open on.
    func test_copyThenRestore_isALosslessRoundTripForEveryAffectedCue() async throws {
        let originalA = [
            CueRightHolder(
                party: .person(UUID()), role: .composer, performanceBroadcastShare: 100, mechanicalRightsShare: 100
            ),
        ]
        let originalB = [
            CueRightHolder(
                party: .person(UUID()), role: .composer, performanceBroadcastShare: 50, mechanicalRightsShare: 50
            ),
            CueRightHolder(
                party: .person(UUID()), role: .author, performanceBroadcastShare: 50, mechanicalRightsShare: 50
            ),
        ]
        let originalC: [CueRightHolder] = []
        let cueA = UpdateCueUseCaseTests.makeCue(title: "A", rightHolders: originalA)
        let cueB = UpdateCueUseCaseTests.makeCue(title: "B", startSeconds: 200, rightHolders: originalB)
        let cueC = UpdateCueUseCaseTests.makeCue(title: "C", startSeconds: 300, rightHolders: originalC)
        let project = UpdateCueUseCaseTests.makeProject(cues: [cueA, cueB, cueC])
        let repository = InMemoryProjectRepository(projects: [project])
        let useCase = UpdateCueUseCase(projectRepository: repository)

        let snapshot: [Cue.ID: [CueRightHolder]] = [cueA.id: originalA, cueB.id: originalB, cueC.id: originalC]

        _ = try await useCase.copyRightHolders(projectID: project.id, rightHolders: originalA)
        let afterCopy = try await repository.fetch(id: project.id)
        // Confirm the copy actually changed B and C before restoring —
        // otherwise this test could pass for the wrong reason.
        XCTAssertEqual(afterCopy?.cues.first { $0.id == cueB.id }?.rightHolders, originalA)
        XCTAssertEqual(afterCopy?.cues.first { $0.id == cueC.id }?.rightHolders, originalA)

        _ = try await useCase.restoreRightHolders(projectID: project.id, snapshot: snapshot)

        let restored = try await repository.fetch(id: project.id)
        XCTAssertEqual(restored?.cues.first { $0.id == cueA.id }?.rightHolders, originalA)
        XCTAssertEqual(restored?.cues.first { $0.id == cueB.id }?.rightHolders, originalB)
        XCTAssertEqual(restored?.cues.first { $0.id == cueC.id }?.rightHolders, originalC)
    }
}
