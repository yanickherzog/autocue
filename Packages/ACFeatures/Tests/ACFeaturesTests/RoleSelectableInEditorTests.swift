import ACCore
@testable import ACFeatures
import XCTest

/// `CueRightHolderRole.selectableInEditor` (`CueRightHolderEditorView.swift`)
/// — a plain, non-View static value, so directly unit-testable
/// (`CONTRIBUTING.md` §5/§7) despite living in a View file.
///
/// Pins the exact current list so a future session can't silently re-narrow
/// or re-widen it without the change being visible in a diff — see
/// `docs/DECISIONS.md`, 2026-09-27, for why `.performer` is selectable again
/// while `.author` stays hidden.
final class RoleSelectableInEditorTests: XCTestCase {
    func test_selectableInEditor_offersComposerArrangerPublisherPerformer_notAuthor() {
        XCTAssertEqual(
            CueRightHolderRole.selectableInEditor,
            [.composer, .arranger, .publisher, .performer]
        )
    }

    func test_selectableInEditor_excludesAuthor() {
        XCTAssertFalse(CueRightHolderRole.selectableInEditor.contains(.author))
    }

    func test_selectableInEditor_includesPerformer() {
        XCTAssertTrue(CueRightHolderRole.selectableInEditor.contains(.performer))
    }
}
