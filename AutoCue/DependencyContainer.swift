import ACAudioKit
import ACCore
import ACFeatures
import ACPersistence
import Foundation
import SwiftData

/// The only type in the codebase allowed to construct a concrete Repository
/// or Use Case (`CLAUDE.md`, "Dependency Injection Pattern"). Constructed
/// exactly once, in `AutoCueApp`, at launch. Gains one factory method per
/// top-level Feature ViewModel as later Deliverables need them —
/// `makeSetupViewModel(for:)`/`makeRightHolderDirectoryViewModel(for:)` are
/// `ROADMAP.md` D7's additions, `makeAudioImportViewModel(for:)` is D8's,
/// `makeCueSheetSectionViewModel(for:)`/`makeCueDetectionViewModel(for:)`/
/// `makeCueDetectionReviewViewModel(for:)` are D9's, alongside the existing
/// `makeProjectLibraryViewModel()` from D6.
@MainActor
final class DependencyContainer {
    private let projectRepository: ProjectRepository
    private let audioAnalysisRepository: AudioAnalysisRepository

    init() {
        let modelContainer = Self.makeModelContainer()
        projectRepository = ProjectRepositoryImpl(modelContainer: modelContainer)
        audioAnalysisRepository = AudioAnalysisRepositoryImpl()
    }

    func makeProjectLibraryViewModel() -> ProjectLibraryViewModel {
        ProjectLibraryViewModel(
            observeProjectsUseCase: ObserveProjectsUseCase(projectRepository: projectRepository),
            createProjectUseCase: CreateProjectUseCase(projectRepository: projectRepository),
            deleteProjectUseCase: DeleteProjectUseCase(projectRepository: projectRepository)
        )
    }

    func makeSetupViewModel(for projectID: Project.ID) -> SetupViewModel {
        SetupViewModel(
            projectID: projectID,
            observeProjectsUseCase: ObserveProjectsUseCase(projectRepository: projectRepository),
            updateSetupUseCase: UpdateSetupUseCase(projectRepository: projectRepository)
        )
    }

    func makeRightHolderDirectoryViewModel(for projectID: Project.ID) -> RightHolderDirectoryViewModel {
        RightHolderDirectoryViewModel(
            projectID: projectID,
            observeProjectsUseCase: ObserveProjectsUseCase(projectRepository: projectRepository),
            updateRightHolderDirectoryUseCase: UpdateRightHolderDirectoryUseCase(projectRepository: projectRepository),
            deleteRightHolderUseCase: DeleteRightHolderUseCase(projectRepository: projectRepository)
        )
    }

    func makeAudioImportViewModel(for projectID: Project.ID) -> AudioImportViewModel {
        AudioImportViewModel(
            projectID: projectID,
            importAudioUseCase: ImportAudioUseCase(
                audioAnalysisRepository: audioAnalysisRepository,
                projectRepository: projectRepository
            ),
            generateWaveformPeaksUseCase: GenerateWaveformPeaksUseCase(
                audioAnalysisRepository: audioAnalysisRepository,
                projectRepository: projectRepository
            )
        )
    }

    func makeCueSheetSectionViewModel(for projectID: Project.ID) -> CueSheetSectionViewModel {
        CueSheetSectionViewModel(
            projectID: projectID,
            observeProjectsUseCase: ObserveProjectsUseCase(projectRepository: projectRepository)
        )
    }

    func makeCueDetectionViewModel(for projectID: Project.ID) -> CueDetectionViewModel {
        CueDetectionViewModel(
            projectID: projectID,
            detectCuesUseCase: DetectCuesUseCase(
                audioAnalysisRepository: audioAnalysisRepository,
                projectRepository: projectRepository
            ),
            observeProjectsUseCase: ObserveProjectsUseCase(projectRepository: projectRepository)
        )
    }

    /// `AudioPlaybackControllerImpl` is constructed fresh per call — one
    /// instance per window, never shared across windows, matching every
    /// other per-window ViewModel's own construction lifetime
    /// (`CLAUDE.md`, "Document & Window Model").
    func makeCueDetectionReviewViewModel(for projectID: Project.ID) -> CueDetectionReviewViewModel {
        CueDetectionReviewViewModel(
            projectID: projectID,
            observeProjectsUseCase: ObserveProjectsUseCase(projectRepository: projectRepository),
            generateWaveformDetailUseCase: GenerateWaveformDetailUseCase(
                audioAnalysisRepository: audioAnalysisRepository,
                projectRepository: projectRepository
            ),
            updateCueUseCase: UpdateCueUseCase(projectRepository: projectRepository),
            audioPlaybackController: AudioPlaybackControllerImpl()
        )
    }

    /// The real, on-disk `ModelContainer` — deliberately left out of scope by
    /// `ACPersistence` (D4), since no App target/entitlements existed yet to
    /// decide a real store location against. No explicit `url:` override:
    /// omitting it lets SwiftData resolve its own default location, which
    /// lands inside the App Sandbox container automatically once
    /// `AutoCue.entitlements`' `com.apple.security.app-sandbox` entitlement
    /// is on (`ROADMAP.md` D6/T6.1) — there's nothing to hand-roll here.
    private static func makeModelContainer() -> ModelContainer {
        let schema = ProjectRepositoryImpl.makeSchema()
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Unrecoverable at launch: persistence is this app's sole
            // source of truth for Project data (CLAUDE.md, "Single Source
            // of Truth") — there is no reduced-functionality mode to fall
            // back to if the store can't be opened.
            fatalError("Failed to initialize the persistent store: \(error)")
        }
    }
}
