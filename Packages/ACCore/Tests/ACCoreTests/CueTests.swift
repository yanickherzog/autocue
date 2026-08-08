@testable import ACCore
import XCTest

final class CueTests: XCTestCase {
    private static func makeRightHolder() -> CueRightHolder {
        CueRightHolder(
            party: .person(UUID()),
            role: .composer,
            performanceBroadcastShare: 100,
            mechanicalRightsShare: 100
        )
    }

    func test_equatableRoundTrip_copyEqualsOriginal() {
        let original = Cue(
            title: "Alpine Theme",
            duration: MediaDuration(seconds: 120),
            rightHolders: [],
            source: .manual
        )
        let copy = original
        XCTAssertEqual(original, copy)
    }

    func test_differingID_makesOtherwiseIdenticalCuesUnequal() {
        let first = Cue(
            id: UUID(),
            title: "Alpine Theme",
            duration: MediaDuration(seconds: 120),
            rightHolders: [],
            source: .manual
        )
        let second = Cue(
            id: UUID(),
            title: "Alpine Theme",
            duration: MediaDuration(seconds: 120),
            rightHolders: [],
            source: .manual
        )
        XCTAssertNotEqual(first, second)
    }

    func test_omittedID_generatesAFreshUUIDPerInstance() {
        let first = Cue(title: "Alpine Theme", duration: MediaDuration(seconds: 120), rightHolders: [], source: .manual)
        let second = Cue(
            title: "Alpine Theme",
            duration: MediaDuration(seconds: 120),
            rightHolders: [],
            source: .manual
        )
        XCTAssertNotEqual(first.id, second.id)
    }

    func test_isArrangementOfProtectedOriginal_defaultsToFalse() {
        let cue = Cue(title: "Alpine Theme", duration: MediaDuration(seconds: 120), rightHolders: [], source: .manual)
        XCTAssertFalse(cue.isArrangementOfProtectedOriginal)
    }

    func test_optionalFields_defaultToNilWhenOmitted() {
        let cue = Cue(title: "Alpine Theme", duration: MediaDuration(seconds: 120), rightHolders: [], source: .manual)

        XCTAssertNil(cue.workNumber)
        XCTAssertNil(cue.startTimecode)
        XCTAssertNil(cue.notes)
    }

    func test_fieldsArePreservedExactlyAsInitialized() {
        let id = UUID()
        let rightHolder = Self.makeRightHolder()
        let startTimecode = Timecode(offsetSeconds: 42)

        let cue = Cue(
            id: id,
            title: "Alpine Theme",
            workNumber: "W-123",
            duration: MediaDuration(seconds: 120),
            rightHolders: [rightHolder],
            isArrangementOfProtectedOriginal: true,
            source: .detectedFromAudio,
            startTimecode: startTimecode,
            notes: "Loud entrance"
        )

        XCTAssertEqual(cue.id, id)
        XCTAssertEqual(cue.title, "Alpine Theme")
        XCTAssertEqual(cue.workNumber, "W-123")
        XCTAssertEqual(cue.duration, MediaDuration(seconds: 120))
        XCTAssertEqual(cue.rightHolders, [rightHolder])
        XCTAssertTrue(cue.isArrangementOfProtectedOriginal)
        XCTAssertEqual(cue.source, .detectedFromAudio)
        XCTAssertEqual(cue.startTimecode, startTimecode)
        XCTAssertEqual(cue.notes, "Loud entrance")
    }
}

final class CueSourceTests: XCTestCase {
    func test_allThreeCasesAreDistinct() {
        XCTAssertNotEqual(CueSource.embeddedMarker, .detectedFromAudio)
        XCTAssertNotEqual(CueSource.embeddedMarker, .manual)
        XCTAssertNotEqual(CueSource.detectedFromAudio, .manual)
    }
}
