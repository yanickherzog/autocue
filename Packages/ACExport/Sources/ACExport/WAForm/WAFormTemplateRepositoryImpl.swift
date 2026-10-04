import ACCore
import Foundation

/// The real `WAFormTemplateRepository` implementation (`ROADMAP.md` D12).
///
/// **Copies the user's selected files into AutoCue's own private container
/// (`WAFormTemplateStorage`) rather than tracking them by security-scoped
/// bookmark** — a deliberate reversal of this type's original D12/T12.1
/// design (`docs/DECISIONS.md`, D12/T12.4). The original design mirrored
/// `AudioAnalysisRepositoryImpl`'s bookmark pattern defensively, assuming
/// the same staleness risk `AudioAsset` genuinely has applied here too. A
/// real relaunch-survival test on that design actually passed, but the
/// user's explicit requirement was a fully automatic experience with zero
/// ongoing dependency on the original external file — a private copy
/// removes that dependency class entirely, which bookmarks (even working
/// ones) never fully do. Still `UserDefaults`-backed for the small amount
/// of display metadata (`WAFormTemplateReference`), the same lightweight,
/// non-`SwiftData` precedent `ProjectWindowFrameStore` already establishes.
public struct WAFormTemplateRepositoryImpl: WAFormTemplateRepository, @unchecked Sendable {
    private enum Key {
        static let mainFormFileName = "WAFormTemplate.mainFormFileName"
        static let continuationFormFileName = "WAFormTemplate.continuationFormFileName"
        static let importedAt = "WAFormTemplate.importedAt"
    }

    public enum TemplateError: Error, Equatable {
        case sourceAccessDenied
    }

    /// `UserDefaults` is documented by Apple as safe for concurrent access
    /// from any thread — this SDK's `Foundation` just hasn't retroactively
    /// marked the class `Sendable` yet, which is the one reason this type
    /// needs `@unchecked Sendable` above rather than plain `Sendable`.
    private let defaults: UserDefaults
    /// Injectable override for `WAFormTemplateStorage.fileURLs(baseDirectory:)`
    /// — `nil` in production (the real Application Support directory); real
    /// tests pass a fresh temporary directory, the same isolation `defaults`
    /// already provides via `UserDefaults(suiteName:)`. See
    /// `WAFormTemplateStorage`'s own doc comment for why this exists at all.
    private let storageDirectory: URL?

    public init(defaults: UserDefaults = .standard, storageDirectory: URL? = nil) {
        self.defaults = defaults
        self.storageDirectory = storageDirectory
    }

    public func importTemplate(mainFormURL: URL, continuationFormURL: URL) throws -> WAFormTemplateReference {
        let destination = try WAFormTemplateStorage.fileURLs(baseDirectory: storageDirectory)
        try Self.copy(from: mainFormURL, to: destination.mainFormURL)
        try Self.copy(from: continuationFormURL, to: destination.continuationFormURL)

        let reference = WAFormTemplateReference(
            mainFormFileName: mainFormURL.lastPathComponent,
            continuationFormFileName: continuationFormURL.lastPathComponent,
            importedAt: Date()
        )
        store(reference)
        return reference
    }

    public func currentTemplate() -> WAFormTemplateReference? {
        guard
            let mainFormFileName = defaults.string(forKey: Key.mainFormFileName),
            let continuationFormFileName = defaults.string(forKey: Key.continuationFormFileName),
            let destination = try? WAFormTemplateStorage.fileURLs(baseDirectory: storageDirectory),
            FileManager.default.fileExists(atPath: destination.mainFormURL.path),
            FileManager.default.fileExists(atPath: destination.continuationFormURL.path)
        else { return nil }
        let importedAt = Date(timeIntervalSince1970: defaults.double(forKey: Key.importedAt))
        return WAFormTemplateReference(
            mainFormFileName: mainFormFileName,
            continuationFormFileName: continuationFormFileName,
            importedAt: importedAt
        )
    }

    public func templateFileURLs() -> (mainFormURL: URL, continuationFormURL: URL)? {
        guard
            currentTemplate() != nil,
            let destination = try? WAFormTemplateStorage.fileURLs(baseDirectory: storageDirectory)
        else { return nil }
        return destination
    }

    private func store(_ reference: WAFormTemplateReference) {
        defaults.set(reference.mainFormFileName, forKey: Key.mainFormFileName)
        defaults.set(reference.continuationFormFileName, forKey: Key.continuationFormFileName)
        defaults.set(reference.importedAt.timeIntervalSince1970, forKey: Key.importedAt)
    }

    /// Brackets the user-selected source `URL` with real security-scoped
    /// access (the same discipline every other import path in this app
    /// uses, `SPEC.md` §4.10) for just long enough to copy its bytes —
    /// unlike `AudioAsset`'s bookmark, nothing about this access needs to
    /// outlive this one call.
    private static func copy(from source: URL, to destination: URL) throws {
        guard source.startAccessingSecurityScopedResource() else {
            throw TemplateError.sourceAccessDenied
        }
        defer { source.stopAccessingSecurityScopedResource() }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
    }
}
