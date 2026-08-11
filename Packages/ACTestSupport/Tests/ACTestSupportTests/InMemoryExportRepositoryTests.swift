import ACCore
@testable import ACTestSupport
import XCTest

final class InMemoryExportRepositoryTests: XCTestCase {
    private static func makeProject() -> Project {
        Project(
            name: "Reel One",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            setup: Setup(
                title: "A Swiss Story",
                producer: [.person(UUID())],
                directorOrPrincipal: [.person(UUID())],
                productionRuntime: MediaDuration(seconds: 5400),
                totalMusicRuntime: MediaDuration(seconds: 600),
                productionYear: 2026,
                containsAdditionalUndeclaredWorks: .no,
                productionTypes: [.documentaryFilm],
                declarant: .person(UUID()),
                declarationDate: Date(timeIntervalSince1970: 0)
            )
        )
    }

    func test_export_streamCompletesWithTheConfiguredURL() async throws {
        let expectedURL = URL(fileURLWithPath: "/tmp/cue-sheet.pdf")
        let repository = InMemoryExportRepository(exportedURL: expectedURL)

        var results: [URL] = []
        for try await event in repository.export(
            project: Self.makeProject(),
            format: .pdf,
            to: URL(fileURLWithPath: "/tmp/destination")
        ) {
            if case let .completed(url) = event {
                results.append(url)
            }
        }

        XCTAssertEqual(results, [expectedURL])
    }
}
