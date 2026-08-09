@testable import ACPersistence
import SwiftData

/// A fresh, real, in-memory `ModelContainer` per call — never a mock of
/// SwiftData (`CONTRIBUTING.md` §5). Every test in this target gets its own
/// container so tests can't leak state into each other.
func makeInMemoryContainer() throws -> ModelContainer {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: ProjectRepositoryImpl.makeSchema(), configurations: configuration)
}
