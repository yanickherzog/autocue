import ACCore
@testable import ACExport
import ACTestSupport
import CoreGraphics
import CoreText
import PDFKit
import XCTest

/// Real PDF generation against a real (synthetic, not SUISA's copyrighted
/// form — see `WAFormTemplateReference`'s own doc comment on why AutoCue
/// never bundles or commits SUISA's real file) multi-page template, per
/// `CONTRIBUTING.md` §5. Confirms the actual mechanism — drawing overlay
/// content on top of a template page via `CGPDFDocument`/`drawPDFPage` —
/// works correctly, independent of what the template's own content is.
final class WAFormRendererTests: XCTestCase {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
    }

    /// A minimal, synthetic N-page blank PDF — stands in for a real WA Film
    /// template file without ever embedding SUISA's own copyrighted content
    /// into this repository's test fixtures.
    private func makeSyntheticTemplate(pageCount: Int) throws -> (url: URL, document: CGPDFDocument) {
        let url = temporaryURL()
        guard let consumer = CGDataConsumer(url: url as CFURL) else {
            throw XCTSkip("Could not create data consumer")
        }
        var mediaBox = CGRect(
            x: 0,
            y: 0,
            width: WAFormLayoutComputer.pageWidth,
            height: WAFormLayoutComputer.pageHeight
        )
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw XCTSkip("Could not create PDF context")
        }
        for pageIndex in 0 ..< pageCount {
            context.beginPDFPage(nil)
            // A real, visible marker distinguishing each synthetic page —
            // lets `test_render_eachOutputPage_carriesItsOwnTemplatePagesBackgroundMarker`
            // confirm the *correct* template page was used as each output
            // page's background, not just that *some* background was drawn.
            // Drawn via real Core Text (not `NSString.draw`, which needs an
            // `NSGraphicsContext` wrapper this raw `CGContext` doesn't have).
            let marker = "TEMPLATE PAGE \(pageIndex)"
            let font = CTFontCreateWithName("Helvetica" as CFString, 10, nil)
            let attributedString = NSAttributedString(
                string: marker,
                attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
            )
            let line = CTLineCreateWithAttributedString(attributedString)
            context.textPosition = CGPoint(x: 20, y: 20)
            CTLineDraw(line, context)
            context.endPDFPage()
        }
        context.closePDF()

        guard let document = CGPDFDocument(url as CFURL) else {
            throw XCTSkip("Could not reopen synthetic template as CGPDFDocument")
        }
        return (url, document)
    }

    func test_render_producesARealPDFWithOneOutputPagePerInputLayoutPage() throws {
        let (mainURL, mainDocument) = try makeSyntheticTemplate(pageCount: 2)
        let (continuationURL, continuationDocument) = try makeSyntheticTemplate(pageCount: 3)
        defer {
            try? FileManager.default.removeItem(at: mainURL)
            try? FileManager.default.removeItem(at: continuationURL)
        }

        let project = ProjectFixture.make()
        let pages = WAFormLayoutComputer.computeLayout(for: project, continuationPagesAvailable: 3)

        let outputURL = temporaryURL()
        defer { try? FileManager.default.removeItem(at: outputURL) }
        try WAFormRenderer.render(
            pages,
            mainFormDocument: mainDocument,
            continuationFormDocument: continuationDocument,
            mainPageCount: 2,
            to: outputURL
        )

        guard let outputProvider = CGDataProvider(url: outputURL as CFURL),
              let outputDocument = CGPDFDocument(outputProvider)
        else {
            XCTFail("Could not open the rendered output as a PDF")
            return
        }
        XCTAssertEqual(outputDocument.numberOfPages, pages.count)
    }

    /// Confirms the actual overlay/background mechanism, not just page
    /// count: output page 0 carries main-template page 0's marker plus the
    /// real `Setup.title` overlay text drawn on top of it.
    func test_render_eachOutputPage_carriesItsOwnTemplatePagesBackgroundMarker() throws {
        let (mainURL, mainDocument) = try makeSyntheticTemplate(pageCount: 2)
        let (continuationURL, continuationDocument) = try makeSyntheticTemplate(pageCount: 1)
        defer {
            try? FileManager.default.removeItem(at: mainURL)
            try? FileManager.default.removeItem(at: continuationURL)
        }

        let project = ProjectFixture.make()
        let pages = WAFormLayoutComputer.computeLayout(for: project, continuationPagesAvailable: 1)

        let outputURL = temporaryURL()
        defer { try? FileManager.default.removeItem(at: outputURL) }
        try WAFormRenderer.render(
            pages,
            mainFormDocument: mainDocument,
            continuationFormDocument: continuationDocument,
            mainPageCount: 2,
            to: outputURL
        )

        let document = try XCTUnwrap(PDFDocument(url: outputURL))
        let page0Text = document.page(at: 0)?.string ?? ""
        let page1Text = document.page(at: 1)?.string ?? ""
        XCTAssertTrue(page0Text.contains("TEMPLATE PAGE 0"))
        XCTAssertTrue(page1Text.contains("TEMPLATE PAGE 1"))
        XCTAssertTrue(page0Text.contains(project.setup.title))
    }

    /// A real, self-caught regression this test exists specifically to
    /// guard against — the exact same class of bug
    /// `PDFCueSheetRendererTests.test_render_everyCueTitle_isActuallyVisibleInTheRenderedText`
    /// already guards for table rows: confirmed via a real rendered-output
    /// visual check (against the real reference files, not a mock) that a
    /// checkbox's own real measured box height (~8.87pt) was too tight for
    /// `CTFrameDraw` to actually render an 8pt bold "X" inside it —
    /// `checkboxMark(at:checked:)` drew a real, non-empty element into the
    /// computed layout, but the glyph was silently dropped at render time
    /// and never appeared in the output at all. Fixed by padding the mark's
    /// own frame height (`+Checkboxes.swift`); this test confirms the fix
    /// holds via the actual rendered PDF's real extracted text, not just
    /// the computed layout's own element list.
    func test_render_aCheckedCheckbox_itsMarkIsActuallyVisibleInTheRenderedText() throws {
        let (mainURL, mainDocument) = try makeSyntheticTemplate(pageCount: 2)
        let (continuationURL, continuationDocument) = try makeSyntheticTemplate(pageCount: 1)
        defer {
            try? FileManager.default.removeItem(at: mainURL)
            try? FileManager.default.removeItem(at: continuationURL)
        }

        var project = ProjectFixture.makeMinimal()
        project = Project(
            id: project.id,
            name: project.name,
            createdAt: project.createdAt,
            updatedAt: project.updatedAt,
            setup: Setup(
                title: project.setup.title,
                producer: project.setup.producer,
                directorOrPrincipal: project.setup.directorOrPrincipal,
                productionRuntime: project.setup.productionRuntime,
                totalMusicRuntime: project.setup.totalMusicRuntime,
                productionYear: project.setup.productionYear,
                containsAdditionalUndeclaredWorks: .notKnown,
                productionTypes: [.documentaryFilm],
                declarant: project.setup.declarant,
                declarationDate: project.setup.declarationDate
            ),
            cues: []
        )
        let pages = WAFormLayoutComputer.computeLayout(for: project, continuationPagesAvailable: 1)

        let outputURL = temporaryURL()
        defer { try? FileManager.default.removeItem(at: outputURL) }
        try WAFormRenderer.render(
            pages,
            mainFormDocument: mainDocument,
            continuationFormDocument: continuationDocument,
            mainPageCount: 2,
            to: outputURL
        )

        let document = try XCTUnwrap(PDFDocument(url: outputURL))
        let page0Text = document.page(at: 0)?.string ?? ""
        XCTAssertTrue(page0Text.contains("X"), "No checkbox mark is actually visible in the rendered output")
    }

    /// A second real, self-caught regression in the same family as the
    /// checkbox one above — found via the same real rendered-output visual
    /// check, this time against a realistic fixture with a subtitle and a
    /// resolved party address (both genuinely multi-line `"\n"`-joined
    /// content): `WAFormLayoutComputer.text(_:x:y:width:font:)`'s own flat
    /// `height: 14` (one line's worth) silently dropped every line past the
    /// first — a title's subtitle, and a declarant's entire address, simply
    /// never appeared in the rendered output despite being real, present
    /// elements in the computed layout. Fixed by sizing the frame's height
    /// to the string's real line count; this test confirms the fix via the
    /// actual rendered PDF's real extracted text.
    func test_render_multiLineText_everyLineIsActuallyVisibleInTheRenderedText() throws {
        let (mainURL, mainDocument) = try makeSyntheticTemplate(pageCount: 2)
        let (continuationURL, continuationDocument) = try makeSyntheticTemplate(pageCount: 1)
        defer {
            try? FileManager.default.removeItem(at: mainURL)
            try? FileManager.default.removeItem(at: continuationURL)
        }

        var project = ProjectFixture.makeMinimal()
        project = Project(
            id: project.id,
            name: project.name,
            createdAt: project.createdAt,
            updatedAt: project.updatedAt,
            setup: Setup(
                title: project.setup.title,
                subtitle: "A Real Subtitle Line",
                producer: project.setup.producer,
                directorOrPrincipal: project.setup.directorOrPrincipal,
                productionRuntime: project.setup.productionRuntime,
                totalMusicRuntime: project.setup.totalMusicRuntime,
                productionYear: project.setup.productionYear,
                containsAdditionalUndeclaredWorks: project.setup.containsAdditionalUndeclaredWorks,
                productionTypes: project.setup.productionTypes,
                declarant: project.setup.declarant,
                declarationDate: project.setup.declarationDate
            ),
            cues: []
        )
        let pages = WAFormLayoutComputer.computeLayout(for: project, continuationPagesAvailable: 1)

        let outputURL = temporaryURL()
        defer { try? FileManager.default.removeItem(at: outputURL) }
        try WAFormRenderer.render(
            pages,
            mainFormDocument: mainDocument,
            continuationFormDocument: continuationDocument,
            mainPageCount: 2,
            to: outputURL
        )

        let document = try XCTUnwrap(PDFDocument(url: outputURL))
        let page0Text = document.page(at: 0)?.string ?? ""
        XCTAssertTrue(page0Text.contains(project.setup.title))
        XCTAssertTrue(page0Text.contains("A Real Subtitle Line"), "The second line of multi-line text was not rendered")
    }

    func test_render_missingTemplatePage_throwsRatherThanCrashing() throws {
        let (mainURL, mainDocument) = try makeSyntheticTemplate(pageCount: 2)
        // Only 1 real continuation page, but the layout below is computed
        // as if 2 were available — a deliberate inconsistency (bypassing
        // `WAFormLayoutComputer`'s own capping, which `ExportRepositoryImpl`
        // always applies in real use via the template's *actual* page
        // count) to exercise this renderer's own defensive error path
        // directly, the same "don't just trust the caller" discipline as
        // `PDFCueSheetRenderer`'s own error cases.
        let (continuationURL, continuationDocument) = try makeSyntheticTemplate(pageCount: 1)
        defer {
            try? FileManager.default.removeItem(at: mainURL)
            try? FileManager.default.removeItem(at: continuationURL)
        }

        let cues = (0 ..< 13).map { index in
            Cue(
                title: "Cue \(index)",
                duration: MediaDuration(seconds: 30),
                rightHolders: [
                    CueRightHolder(
                        party: .person(UUID()),
                        role: .composer,
                        performanceBroadcastShare: 100,
                        mechanicalRightsShare: 100
                    ),
                ],
                source: .manual
            )
        }
        var project = ProjectFixture.makeMinimal()
        project = Project(
            id: project.id,
            name: project.name,
            createdAt: project.createdAt,
            updatedAt: project.updatedAt,
            setup: project.setup,
            cues: cues
        )
        let pages = WAFormLayoutComputer.computeLayout(for: project, continuationPagesAvailable: 2)

        let outputURL = temporaryURL()
        defer { try? FileManager.default.removeItem(at: outputURL) }
        XCTAssertThrowsError(try WAFormRenderer.render(
            pages,
            mainFormDocument: mainDocument,
            continuationFormDocument: continuationDocument,
            mainPageCount: 2,
            to: outputURL
        ))
    }
}
