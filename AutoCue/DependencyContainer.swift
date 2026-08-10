import ACCore
import ACFeatures
import ACPersistence
import Foundation
import SwiftData

/// The only type in the codebase allowed to construct a concrete Repository
/// or Use Case (`CLAUDE.md`, "Dependency Injection Pattern"). Constructed
/// exactly once, in `AutoCueApp`, at launch. Gains one factory method per
/// top-level Feature ViewModel as later Deliverables need them — only
/// `makeProjectLibraryViewModel()` exists yet, since it's the only Feature
/// `ROADMAP.md` D6 actually builds; adding `makeSetupViewModel(for:)` etc.
/// now, before `SetupViewModel` exists, would be exactly the kind of
/// half-built stub `CONTRIBUTING.md` §2 warns against.
@MainActor
final class DependencyContainer {
    private let projectRepository: ProjectRepository

    init() {
        let modelContainer = Self.makeModelContainer()
        projectRepository = ProjectRepositoryImpl(modelContainer: modelContainer)
    }

    func makeProjectLibraryViewModel() -> ProjectLibraryViewModel {
        ProjectLibraryViewModel(
            observeProjectsUseCase: ObserveProjectsUseCase(projectRepository: projectRepository),
            createProjectUseCase: CreateProjectUseCase(projectRepository: projectRepository),
            deleteProjectUseCase: DeleteProjectUseCase(projectRepository: projectRepository)
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
