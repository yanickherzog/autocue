@testable import ACCore
import XCTest

final class SettingsTests: XCTestCase {
    func test_equatableRoundTrip_copyEqualsOriginal() {
        let original = Settings()
        let copy = original
        XCTAssertEqual(original, copy)
    }

    func test_defaults_matchSpec() {
        let settings = Settings()

        XCTAssertNil(settings.defaultDeclarant)
        XCTAssertNil(settings.defaultProductionCountry)
        XCTAssertEqual(settings.exportLanguage, .en)
        XCTAssertTrue(settings.autoComputeTotalMusicRuntime)
        XCTAssertEqual(settings.shareValidationStrictness, .warnOnly)
        XCTAssertEqual(settings.defaultExportFormat, .both)
        XCTAssertEqual(settings.audioAnalysisDefaults, AnalysisSettings())
    }

    func test_everyField_isOverridableExplicitly() {
        let declarant = Party.person(UUID())
        let analysisDefaults = AnalysisSettings(silenceThresholdDb: -30)

        let settings = Settings(
            defaultDeclarant: declarant,
            defaultProductionCountry: "CH",
            exportLanguage: .de,
            autoComputeTotalMusicRuntime: false,
            shareValidationStrictness: .blockExport,
            defaultExportFormat: .pdf,
            audioAnalysisDefaults: analysisDefaults
        )

        XCTAssertEqual(settings.defaultDeclarant, declarant)
        XCTAssertEqual(settings.defaultProductionCountry, "CH")
        XCTAssertEqual(settings.exportLanguage, .de)
        XCTAssertFalse(settings.autoComputeTotalMusicRuntime)
        XCTAssertEqual(settings.shareValidationStrictness, .blockExport)
        XCTAssertEqual(settings.defaultExportFormat, .pdf)
        XCTAssertEqual(settings.audioAnalysisDefaults, analysisDefaults)
    }
}

final class ExportLanguageTests: XCTestCase {
    func test_allFourCasesAreDistinct() {
        let languages: [ExportLanguage] = [.de, .fr, .it, .en]
        XCTAssertEqual(Set(languages.map { "\($0)" }).count, 4)
    }
}

final class ShareValidationStrictnessTests: XCTestCase {
    func test_bothCasesAreDistinct() {
        XCTAssertNotEqual(ShareValidationStrictness.warnOnly, .blockExport)
    }
}

final class ExportFormatTests: XCTestCase {
    func test_allThreeCasesAreDistinct() {
        let formats: [ExportFormat] = [.pdf, .xlsx, .both]
        XCTAssertEqual(Set(formats.map { "\($0)" }).count, 3)
    }
}
