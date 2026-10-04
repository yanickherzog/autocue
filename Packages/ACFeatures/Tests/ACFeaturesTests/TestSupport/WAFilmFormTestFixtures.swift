import ACCore
@testable import ACFeatures
@testable import ACTestSupport
import Foundation

/// Shared fixture/ViewModel-construction helpers for `WAFilmFormViewModelTests`
/// and `WAFilmFormExportViewModelTests` — split across two files/classes
/// purely to satisfy `SwiftLint`'s `type_body_length` (`CONTRIBUTING.md` §8),
/// the same reasoning `ExportViewModelTests`/`ReviewViewModelTests` already
/// split the combined Review & Export screen's tests by concern rather than
/// as one large class.
@MainActor
enum WAFilmFormTestFixtures {
    static func makeValidSetup() -> Setup {
        Setup(
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
    }

    static func makeProject(cues: [Cue] = []) -> Project {
        Project(name: "Reel One", createdAt: Date(), updatedAt: Date(), setup: makeValidSetup(), cues: cues)
    }

    static func makeReference() -> WAFormTemplateReference {
        WAFormTemplateReference(
            mainFormFileName: "WA Film.pdf",
            continuationFormFileName: "WA Film II.pdf",
            importedAt: Date(timeIntervalSince1970: 0)
        )
    }

    static func makeViewModel(
        project: Project,
        projectRepository: InMemoryProjectRepository? = nil,
        templateRepository: InMemoryWAFormTemplateRepository = InMemoryWAFormTemplateRepository(),
        exportRepository: InMemoryExportRepository = InMemoryExportRepository(),
        shareValidationStrictness: ShareValidationStrictness = .warnOnly
    ) -> WAFilmFormViewModel {
        let projectRepository = projectRepository ?? InMemoryProjectRepository(projects: [project])
        return WAFilmFormViewModel(
            projectID: project.id,
            observeProjectsUseCase: ObserveProjectsUseCase(projectRepository: projectRepository),
            waFormTemplateUseCase: WAFormTemplateUseCase(waFormTemplateRepository: templateRepository),
            computeWAFormLayoutUseCase: ComputeWAFormLayoutUseCase(exportRepository: exportRepository),
            validateWAFormUseCase: ValidateWAFormUseCase(exportRepository: exportRepository),
            exportWAFormUseCase: ExportWAFormUseCase(
                projectRepository: projectRepository,
                exportRepository: exportRepository
            ),
            shareValidationStrictness: shareValidationStrictness
        )
    }
}
