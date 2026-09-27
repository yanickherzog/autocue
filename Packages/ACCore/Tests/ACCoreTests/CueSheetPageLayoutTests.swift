@testable import ACCore
import XCTest

final class CueSheetPageLayoutTests: XCTestCase {
    func test_equatableRoundTrip_copyEqualsOriginal() {
        let original = CueSheetPageLayout(
            pageIndex: 0,
            pageCount: 2,
            elements: [
                CueSheetLayoutElement(
                    frame: LayoutRect(x: 1, y: 2, width: 3, height: 4),
                    content: .text("Hello", font: LayoutFontSpec(weight: .bold, size: 9))
                ),
                CueSheetLayoutElement(
                    frame: LayoutRect(x: 0, y: 0, width: 100, height: 1),
                    content: .rule(LayoutRuleSpec(thickness: 0.5))
                ),
            ]
        )
        let copy = original
        XCTAssertEqual(original, copy)
    }

    func test_differingPageIndex_makesLayoutsUnequal() {
        let elements: [CueSheetLayoutElement] = []
        let first = CueSheetPageLayout(pageIndex: 0, pageCount: 2, elements: elements)
        let second = CueSheetPageLayout(pageIndex: 1, pageCount: 2, elements: elements)
        XCTAssertNotEqual(first, second)
    }

    func test_differingContent_makesTextElementsUnequal() {
        let font = LayoutFontSpec(weight: .regular, size: 9)
        let first = CueSheetLayoutElement(
            frame: LayoutRect(x: 0, y: 0, width: 10, height: 10),
            content: .text("A", font: font)
        )
        let second = CueSheetLayoutElement(
            frame: LayoutRect(x: 0, y: 0, width: 10, height: 10),
            content: .text("B", font: font)
        )
        XCTAssertNotEqual(first, second)
    }

    func test_textAndRule_areNeverEqualRegardlessOfFrame() {
        let frame = LayoutRect(x: 0, y: 0, width: 10, height: 10)
        let text = CueSheetLayoutElement(
            frame: frame,
            content: .text("", font: LayoutFontSpec(weight: .regular, size: 9))
        )
        let rule = CueSheetLayoutElement(frame: frame, content: .rule(LayoutRuleSpec(thickness: 1)))
        XCTAssertNotEqual(text, rule)
    }
}
