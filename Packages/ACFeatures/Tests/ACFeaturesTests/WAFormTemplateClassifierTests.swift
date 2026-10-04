@testable import ACFeatures
import XCTest

final class WAFormTemplateClassifierTests: XCTestCase {
    func test_classify_textMentionsWAFilmOnly_mainForm() {
        XCTAssertEqual(
            WAFormTemplateClassifier.classify(text: "SUISA WA Film 2007-01 — Declaration", pageCount: 2),
            .mainForm
        )
    }

    func test_classify_textMentionsWAFilmII_continuationForm() {
        XCTAssertEqual(
            WAFormTemplateClassifier.classify(text: "SUISA WA Film II 2007-01 — Additional Works", pageCount: 5),
            .continuationForm
        )
    }

    func test_classify_germanZusaetzlicheWerke_continuationForm() {
        XCTAssertEqual(
            WAFormTemplateClassifier.classify(text: "Zusätzliche Werke", pageCount: 5),
            .continuationForm
        )
    }

    func test_classify_englishAdditionalWorks_continuationForm() {
        XCTAssertEqual(
            WAFormTemplateClassifier.classify(text: "Additional Works Form", pageCount: 3),
            .continuationForm
        )
    }

    /// The real decisive test: "WA Film II" *contains* the substring
    /// "WA Film" — continuation must win, not fall through to main form.
    func test_classify_continuationTextAlsoContainsPlainWAFilmSubstring_stillContinuationForm() {
        XCTAssertEqual(
            WAFormTemplateClassifier.classify(text: "WA Film II", pageCount: 5),
            .continuationForm
        )
    }

    func test_classify_caseAndDiacriticInsensitive() {
        XCTAssertEqual(
            WAFormTemplateClassifier.classify(text: "wa FILM ii — ZUSATZLICHE WERKE", pageCount: 5),
            .continuationForm
        )
    }

    func test_classify_noTextButTwoPages_fallsBackToMainForm() {
        XCTAssertEqual(WAFormTemplateClassifier.classify(text: nil, pageCount: 2), .mainForm)
    }

    func test_classify_noTextAndNotTwoPages_nil() {
        XCTAssertNil(WAFormTemplateClassifier.classify(text: nil, pageCount: 5))
        XCTAssertNil(WAFormTemplateClassifier.classify(text: "", pageCount: 1))
    }

    func test_classify_unrelatedTextAndPageCount_nil() {
        XCTAssertNil(WAFormTemplateClassifier.classify(text: "An invoice for services rendered", pageCount: 3))
    }
}
