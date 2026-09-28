import ACCore
@testable import ACExport
import ACTestSupport
import CoreGraphics
import PDFKit
import XCTest

/// Real PDF generation, not a mock (`CONTRIBUTING.md` §5) — writes an actual
/// file and inspects it, the same "genuine ZIP/OOXML file" standard
/// `XLSXFeasibilitySpikeTests` already established for the other export
/// format.
final class PDFCueSheetRendererTests: XCTestCase {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
    }

    func test_render_producesAFileStartingWithTheRealPDFSignature() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let pages = CueSheetLayoutComputer.computeLayout(for: ProjectFixture.make())
        try PDFCueSheetRenderer.render(pages, to: url)

        let data = try Data(contentsOf: url)
        let header = try XCTUnwrap(String(bytes: data.prefix(5), encoding: .utf8))
        XCTAssertEqual(header, "%PDF-")
    }

    func test_render_producesANonEmptyFile() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let pages = CueSheetLayoutComputer.computeLayout(for: ProjectFixture.make())
        try PDFCueSheetRenderer.render(pages, to: url)

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = attributes[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, 0)
    }

    func test_render_multiPageLayout_producesAPDFWithMatchingPageCount() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        var project = ProjectFixture.make()
        let extraCues = (0 ..< 40).map { index in
            Cue(
                title: "Filler Cue \(index)",
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
        project = Project(
            id: project.id,
            name: project.name,
            createdAt: project.createdAt,
            updatedAt: project.updatedAt,
            audioAsset: project.audioAsset,
            waveformPeaks: project.waveformPeaks,
            setup: project.setup,
            cues: project.cues + extraCues,
            people: project.people,
            labels: project.labels
        )
        let pages = CueSheetLayoutComputer.computeLayout(for: project)
        try PDFCueSheetRenderer.render(pages, to: url)

        guard let provider = CGDataProvider(url: url as CFURL), let document = CGPDFDocument(provider) else {
            XCTFail("Could not open the rendered file as a PDF")
            return
        }
        XCTAssertEqual(document.numberOfPages, pages.count)
        XCTAssertGreaterThan(pages.count, 1)
    }

    /// A real, self-caught regression this test exists specifically to guard
    /// against: `CueSheetLayoutElement`'s own `content` string is present
    /// regardless of whether the row's *allocated drawing height* was tall
    /// enough to actually render it — `CTFrameDraw` silently drops an entire
    /// line of text if its frame is shorter than one line needs, which a
    /// short single-line row (unlike a long, multi-line-wrapped one) can
    /// trigger from even a small under-allocation. Every other test in this
    /// file inspects `CueSheetPageLayout`'s elements or the PDF's raw
    /// structure (page count, signature) — none of that would have caught a
    /// row that exists in the layout but is invisible in the actual PDF.
    /// This test uses `PDFKit` to extract the real, rendered text (allowed
    /// for verification — `CLAUDE.md` restricts `PDFKit` from *generation*,
    /// not from reading an already-generated file, the same use
    /// `CLAUDE.md`'s own "in-app preview" carve-out describes) and confirms
    /// every cue's title actually appears.
    func test_render_everyCueTitle_isActuallyVisibleInTheRenderedText() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let project = ProjectFixture.make()
        let pages = CueSheetLayoutComputer.computeLayout(for: project)
        try PDFCueSheetRenderer.render(pages, to: url)

        let document = try XCTUnwrap(PDFDocument(url: url))
        let extractedText = document.string ?? ""
        for cue in project.cues {
            let failureMessage = "\"\(cue.title)\" is missing from the rendered PDF's actual text — the row exists "
                + "in the computed layout but its allocated drawing height was too short to render"
            XCTAssertTrue(extractedText.contains(cue.title), failureMessage)
        }
    }

    /// The header-block equivalent of the regression above: a multi-line
    /// "Komponist-IPI" cell (two composers stacked vertically, per the real
    /// cue sheet example, `docs/DECISIONS.md`, 2026-09-27) must actually
    /// render both lines in the real PDF, not just exist as a `\n`-joined
    /// string in `CueSheetPageLayout`'s elements — the same class of gap
    /// `test_render_everyCueTitle_isActuallyVisibleInTheRenderedText` closes
    /// for table rows, applied to a multi-line header cell instead.
    func test_render_multiComposerHeaderCell_bothComposerLinesAreActuallyVisible() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let composerWithIPI = Person(firstName: "Alice", lastName: "WithIPI", ipiNumber: "11111111111")
        let composerWithoutIPI = Person(firstName: "Bob", lastName: "NoIPI")
        let base = ProjectFixture.makeMinimal()
        let cue = Cue(
            title: "Cue One",
            duration: MediaDuration(seconds: 60),
            rightHolders: [
                CueRightHolder(
                    party: .person(composerWithIPI.id),
                    role: .composer,
                    performanceBroadcastShare: 50,
                    mechanicalRightsShare: 50
                ),
                CueRightHolder(
                    party: .person(composerWithoutIPI.id),
                    role: .composer,
                    performanceBroadcastShare: 50,
                    mechanicalRightsShare: 50
                ),
            ],
            source: .manual
        )
        let project = Project(
            id: base.id,
            name: base.name,
            createdAt: base.createdAt,
            updatedAt: base.updatedAt,
            setup: base.setup,
            cues: [cue],
            people: [composerWithIPI, composerWithoutIPI]
        )

        let pages = CueSheetLayoutComputer.computeLayout(for: project)
        try PDFCueSheetRenderer.render(pages, to: url)

        let document = try XCTUnwrap(PDFDocument(url: url))
        let extractedText = document.string ?? ""
        XCTAssertTrue(extractedText.contains("Alice WithIPI, IPI-Nr. 111 11 11 11"))
        XCTAssertTrue(extractedText.contains("Bob NoIPI"))
    }
}
