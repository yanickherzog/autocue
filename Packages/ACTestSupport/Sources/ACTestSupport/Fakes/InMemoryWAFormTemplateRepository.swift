import ACCore
import Foundation

/// An in-memory `WAFormTemplateRepository` fake (`ROADMAP.md` D12) — holds
/// its stored reference in a plain class-boxed property rather than real
/// `UserDefaults`/a real filesystem copy, per `CONTRIBUTING.md` §5
/// ("ViewModels tested against fakes... never against real
/// `AVFoundation`/`SwiftData`" — the same reasoning extends to
/// `UserDefaults`/filesystem-backed Data-layer state).
public final class InMemoryWAFormTemplateRepository: WAFormTemplateRepository, @unchecked Sendable {
    public var storedTemplate: WAFormTemplateReference?
    public var importError: Error?
    /// Canned URLs returned by `templateFileURLs()` once `storedTemplate`
    /// is non-`nil` — real `file://` URLs aren't needed for any `ACCore`/
    /// `ACTestSupport`-level test, since nothing there actually opens them;
    /// only `WAFormPreviewView` (`ACFeatures`, not unit-tested per
    /// `CONTRIBUTING.md` §5/§7) does that, against the real Impl.
    public var fileURLsToReturn: (mainFormURL: URL, continuationFormURL: URL) = (
        mainFormURL: URL(fileURLWithPath: "/tmp/fixture-main-form.pdf"),
        continuationFormURL: URL(fileURLWithPath: "/tmp/fixture-continuation-form.pdf")
    )

    public init(storedTemplate: WAFormTemplateReference? = nil, importError: Error? = nil) {
        self.storedTemplate = storedTemplate
        self.importError = importError
    }

    public func importTemplate(mainFormURL: URL, continuationFormURL: URL) throws -> WAFormTemplateReference {
        if let importError {
            throw importError
        }
        let reference = WAFormTemplateReference(
            mainFormFileName: mainFormURL.lastPathComponent,
            continuationFormFileName: continuationFormURL.lastPathComponent,
            importedAt: Date()
        )
        storedTemplate = reference
        return reference
    }

    public func currentTemplate() -> WAFormTemplateReference? {
        storedTemplate
    }

    public func templateFileURLs() -> (mainFormURL: URL, continuationFormURL: URL)? {
        guard storedTemplate != nil else { return nil }
        return fileURLsToReturn
    }
}
