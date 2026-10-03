import ACCore
import Foundation

/// An in-memory `ComposerProfileRepository` fake — holds its stored profile
/// in a plain class-boxed property rather than real `UserDefaults`, same
/// reasoning as `InMemoryWAFormTemplateRepository`'s own doc comment.
public final class InMemoryComposerProfileRepository: ComposerProfileRepository, @unchecked Sendable {
    public var storedProfile: ComposerProfile?
    public var saveError: Error?

    public init(storedProfile: ComposerProfile? = nil, saveError: Error? = nil) {
        self.storedProfile = storedProfile
        self.saveError = saveError
    }

    public func currentProfile() -> ComposerProfile? {
        storedProfile
    }

    public func saveProfile(_ profile: ComposerProfile) throws {
        if let saveError {
            throw saveError
        }
        storedProfile = profile
    }
}
