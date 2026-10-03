import ACCore
import Foundation

/// The real `WAFormTemplateRepository` implementation (`ROADMAP.md` D12).
///
/// **`UserDefaults`-backed, not `SwiftData`** — deliberate, mirroring
/// `ProjectWindowFrameStore`'s own lightweight, non-`SwiftData` precedent
/// (`AutoCue/ProjectWindowFrameStore.swift`): this is one small, app-level
/// value, not a growing collection of project-scoped records, so the full
/// `ACPersistence`/`SwiftData` machinery would be disproportionate. Reached
/// through a proper `ACCore` protocol (unlike `ProjectWindowFrameStore`,
/// which lives directly in the App target) because both `ACFeatures` and
/// `ACExport` need it, not just the App target.
///
/// Bookmark minting/resolution mirrors `AudioAnalysisRepositoryImpl`'s own
/// pattern exactly (SPEC.md §4.10): security-scoped first, falling back to
/// plain if creation itself fails, independently per file.
public struct WAFormTemplateRepositoryImpl: WAFormTemplateRepository, @unchecked Sendable {
    private enum Key {
        static let mainFormBookmark = "WAFormTemplate.mainFormBookmark"
        static let mainFormAccessMode = "WAFormTemplate.mainFormAccessMode"
        static let mainFormFileName = "WAFormTemplate.mainFormFileName"
        static let continuationFormBookmark = "WAFormTemplate.continuationFormBookmark"
        static let continuationFormAccessMode = "WAFormTemplate.continuationFormAccessMode"
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

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func importTemplate(mainFormURL: URL, continuationFormURL: URL) throws -> WAFormTemplateReference {
        let (mainBookmark, mainMode) = try Self.makeBookmark(for: mainFormURL)
        let (continuationBookmark, continuationMode) = try Self.makeBookmark(for: continuationFormURL)
        let reference = WAFormTemplateReference(
            mainFormBookmark: mainBookmark,
            mainFormAccessMode: mainMode,
            mainFormFileName: mainFormURL.lastPathComponent,
            continuationFormBookmark: continuationBookmark,
            continuationFormAccessMode: continuationMode,
            continuationFormFileName: continuationFormURL.lastPathComponent,
            importedAt: Date()
        )
        store(reference)
        return reference
    }

    public func currentTemplate() -> WAFormTemplateReference? {
        guard
            let mainFormBookmark = defaults.data(forKey: Key.mainFormBookmark),
            let mainModeRaw = defaults.string(forKey: Key.mainFormAccessMode),
            let mainMode = BookmarkAccessMode(rawValue: mainModeRaw),
            let mainFormFileName = defaults.string(forKey: Key.mainFormFileName),
            let continuationFormBookmark = defaults.data(forKey: Key.continuationFormBookmark),
            let continuationModeRaw = defaults.string(forKey: Key.continuationFormAccessMode),
            let continuationMode = BookmarkAccessMode(rawValue: continuationModeRaw),
            let continuationFormFileName = defaults.string(forKey: Key.continuationFormFileName)
        else { return nil }
        let importedAt = Date(timeIntervalSince1970: defaults.double(forKey: Key.importedAt))
        return WAFormTemplateReference(
            mainFormBookmark: mainFormBookmark,
            mainFormAccessMode: mainMode,
            mainFormFileName: mainFormFileName,
            continuationFormBookmark: continuationFormBookmark,
            continuationFormAccessMode: continuationMode,
            continuationFormFileName: continuationFormFileName,
            importedAt: importedAt
        )
    }

    public func refreshBookmarkIfStale(_ reference: WAFormTemplateReference) throws -> WAFormTemplateReference? {
        let refreshedMain = try Self.refreshIfStale(reference.mainFormBookmark, mode: reference.mainFormAccessMode)
        let refreshedContinuation = try Self.refreshIfStale(
            reference.continuationFormBookmark,
            mode: reference.continuationFormAccessMode
        )
        guard refreshedMain != nil || refreshedContinuation != nil else { return nil }
        let updated = WAFormTemplateReference(
            mainFormBookmark: refreshedMain ?? reference.mainFormBookmark,
            mainFormAccessMode: reference.mainFormAccessMode,
            mainFormFileName: reference.mainFormFileName,
            continuationFormBookmark: refreshedContinuation ?? reference.continuationFormBookmark,
            continuationFormAccessMode: reference.continuationFormAccessMode,
            continuationFormFileName: reference.continuationFormFileName,
            importedAt: reference.importedAt
        )
        store(updated)
        return updated
    }

    private func store(_ reference: WAFormTemplateReference) {
        defaults.set(reference.mainFormBookmark, forKey: Key.mainFormBookmark)
        defaults.set(reference.mainFormAccessMode.rawValue, forKey: Key.mainFormAccessMode)
        defaults.set(reference.mainFormFileName, forKey: Key.mainFormFileName)
        defaults.set(reference.continuationFormBookmark, forKey: Key.continuationFormBookmark)
        defaults.set(reference.continuationFormAccessMode.rawValue, forKey: Key.continuationFormAccessMode)
        defaults.set(reference.continuationFormFileName, forKey: Key.continuationFormFileName)
        defaults.set(reference.importedAt.timeIntervalSince1970, forKey: Key.importedAt)
    }

    // MARK: - Bookmark creation and resolution (mirrors AudioAnalysisRepositoryImpl)

    private static func makeBookmark(for url: URL) throws -> (Data, BookmarkAccessMode) {
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            return (bookmark, .securityScoped)
        } catch {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            return (bookmark, .plainFallback)
        }
    }

    private static func refreshIfStale(_ bookmark: Data, mode: BookmarkAccessMode) throws -> Data? {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: mode.resolutionOptions,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        guard isStale else { return nil }
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try url.bookmarkData(options: mode.creationOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Resolves a stored bookmark back to a usable `URL` — package-internal
    /// so `WAFormLayoutComputer`/`WAFormRenderer` (same module) can open the
    /// real template files without duplicating this resolution logic.
    static func resolveURL(bookmark: Data, mode: BookmarkAccessMode) throws -> URL {
        var isStale = false
        return try URL(
            resolvingBookmarkData: bookmark,
            options: mode.resolutionOptions,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }
}

/// Maps `BookmarkAccessMode` to the actual `URL` bookmark options it
/// corresponds to — duplicated from `ACAudioKit`'s identical extension
/// rather than shared, since `ACAudioKit`/`ACExport` never depend on each
/// other (`CLAUDE.md`'s Package Dependency Graph) — the same small,
/// deliberate cross-Data-package duplication `CueSheetLayoutComputer
/// +Formatting.swift`'s own doc comment already establishes as the correct
/// tradeoff for this exact situation.
extension BookmarkAccessMode {
    var creationOptions: URL.BookmarkCreationOptions {
        switch self {
        case .securityScoped: .withSecurityScope
        case .plainFallback: []
        }
    }

    var resolutionOptions: URL.BookmarkResolutionOptions {
        switch self {
        case .securityScoped: .withSecurityScope
        case .plainFallback: []
        }
    }
}
