import ACCore
@testable import ACFeatures
@testable import ACTestSupport
import XCTest

/// `commitRightHolderEdits` (`CueDetectionReviewViewModel
/// +RightHolders.swift`, `ROADMAP.md` D10, second round) — split into its
/// own file mirroring the production split.
///
/// **Add/remove/role/party/attachment editing has no ViewModel-level tests
/// any more.** That logic moved entirely into `CueRightHolderEditorView`
/// (`ACFeatures` Views aren't unit-tested, per `CONTRIBUTING.md` §5/§7) as
/// plain, synchronous mutations on a local `Binding<[CueRightHolder]>` — see
/// `docs/DECISIONS.md` for why. The one thing still worth a ViewModel-level
/// test is the single commit-on-"Done" write path itself.
@MainActor
final class CueDetectionReviewRightHoldersTests: XCTestCase {
    /// **The specific concern flagged before implementation began:** SPEC.md
    /// §4.6 chose `Decimal` for these two fields precisely because it does
    /// exact base-10 arithmetic, with zero tolerance in the 100%-sum check.
    /// This proves the value that survives the full round trip — from a
    /// typed "33.33" string (simulated exactly as `GhostDecimalField` would
    /// produce it) through this one commit call, `UpdateCueUseCase.edit`,
    /// and back out of the repository — is byte-for-byte
    /// `Decimal(string: "33.33")`, not the `Double`-imprecise
    /// `33.32999999999999488` a `Double`-literal construction would silently
    /// produce instead (`docs/REVIEW.md`'s D2 entry).
    func test_commitRightHolderEdits_exactDecimalStringValue_survivesRoundTripUnchanged() async throws {
        let personID = Person.ID()
        let cue = makeCueDetectionReviewCue(startSeconds: 10, duration: 30)
        let env = makeCueDetectionReviewEnvironment(cues: [cue])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 1 }

        let exactShare = try XCTUnwrap(Decimal(string: "33.33"))
        let rightHolders = [
            CueRightHolder(
                party: .person(personID),
                role: .composer,
                performanceBroadcastShare: exactShare,
                mechanicalRightsShare: exactShare
            ),
        ]
        await viewModel.commitRightHolderEdits(cueID: cue.id, rightHolders: rightHolders)

        let updated = try await projectRepository.fetch(id: project.id)
        let stored = try XCTUnwrap(updated?.cues.first?.rightHolders.first?.performanceBroadcastShare)
        XCTAssertEqual(stored, Decimal(string: "33.33"))
        // The failure mode this guards against: a `Double`-routed
        // construction of the same nominal value is NOT exactly equal to
        // `Decimal(string: "33.33")` -- confirming this test would actually
        // catch a regression back to that bug, not just restate the
        // assertion above.
        XCTAssertNotEqual(stored, Decimal(33.33))
        loadTask.cancel()
    }

    func test_commitRightHolderEdits_writesTheWholeListInOneShot_andReclassifiesToManual() async throws {
        let cue = makeCueDetectionReviewCue(startSeconds: 10, duration: 30, source: .detectedFromAudio)
        let env = makeCueDetectionReviewEnvironment(cues: [cue])
        let viewModel = env.viewModel
        let projectRepository = env.projectRepository
        let project = env.project

        let loadTask = Task { await viewModel.load() }
        try await waitUntilCueDetectionReviewConditionMet { viewModel.cues.count == 1 }

        let rightHolders = [
            CueRightHolder(
                party: .person(Person.ID()), role: .composer, performanceBroadcastShare: 60, mechanicalRightsShare: 60
            ),
            CueRightHolder(
                party: .person(Person.ID()), role: .author, performanceBroadcastShare: 40, mechanicalRightsShare: 40
            ),
        ]
        await viewModel.commitRightHolderEdits(cueID: cue.id, rightHolders: rightHolders)

        let updated = try await projectRepository.fetch(id: project.id)
        XCTAssertEqual(updated?.cues.first?.rightHolders, rightHolders)
        XCTAssertEqual(updated?.cues.first?.source, .manual)
        loadTask.cancel()
    }
}
