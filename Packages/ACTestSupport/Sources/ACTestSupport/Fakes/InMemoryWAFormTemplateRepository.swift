import ACCore
import Foundation

/// An in-memory `WAFormTemplateRepository` fake (`ROADMAP.md` D12) — holds
/// its stored reference in a plain class-boxed property rather than real
/// `UserDefaults`, per `CONTRIBUTING.md` §5 ("ViewModels tested against
/// fakes... never against real `AVFoundation`/`SwiftData`" — the same
/// reasoning extends to `UserDefaults`-backed Data-layer state).
public final class InMemoryWAFormTemplateRepository: WAFormTemplateRepository, @unchecked Sendable {
    public var storedTemplate: WAFormTemplateReference?
    public var importError: Error?
    public var refreshedReference: WAFormTemplateReference?

    public init(storedTemplate: WAFormTemplateReference? = nil, importError: Error? = nil) {
        self.storedTemplate = storedTemplate
        self.importError = importError
    }

    public func importTemplate(mainFormURL: URL, continuationFormURL: URL) throws -> WAFormTemplateReference {
        if let importError {
            throw importError
        }
        let reference = WAFormTemplateReference(
            mainFormBookmark: Data(),
            mainFormAccessMode: .securityScoped,
            mainFormFileName: mainFormURL.lastPathComponent,
            continuationFormBookmark: Data(),
            continuationFormAccessMode: .securityScoped,
            continuationFormFileName: continuationFormURL.lastPathComponent,
            importedAt: Date()
        )
        storedTemplate = reference
        return reference
    }

    public func currentTemplate() -> WAFormTemplateReference? {
        storedTemplate
    }

    public func refreshBookmarkIfStale(_: WAFormTemplateReference) throws -> WAFormTemplateReference? {
        refreshedReference
    }
}
