import Foundation

/// The deterministic, app-owned location AutoCue's own private copy of the
/// user's imported WA Film template PDFs lives at (`ROADMAP.md` D12/T12.4) —
/// package-internal, shared by `WAFormTemplateRepositoryImpl` (writes the
/// copies at import time) and `ExportRepositoryImpl` (opens them to render/
/// export), both in this same module.
///
/// **Inside the app's own sandbox container's Application Support
/// directory — never the shipped `.app` bundle itself.** This is what keeps
/// "AutoCue never bundles SUISA's own form" true: the bundle on disk is
/// completely unaffected by what any one user has imported; only that
/// user's own per-account container gains a private copy of a file *they*
/// legitimately supplied. No security-scoped bookmark is needed to read
/// these URLs — the sandbox always grants an app standing access to its own
/// container, unlike a user-selected external location.
///
/// Fixed filenames (`main-form.pdf`/`continuation-form.pdf`), not the
/// user's own original filenames — a re-import simply overwrites them in
/// place. The *original* filenames are preserved separately, for display
/// only, in `WAFormTemplateReference.mainFormFileName`/
/// `.continuationFormFileName`.
enum WAFormTemplateStorage {
    /// Both real file URLs, creating the containing directory first if it
    /// doesn't exist yet (a fresh install/container has none) — safe to call
    /// before either file has actually been written.
    ///
    /// **`baseDirectory` is an injectable override, `nil` in production.**
    /// The real base is the app's own Application Support directory — a
    /// single, fixed, machine-global location with no per-test isolation of
    /// its own. Without this override, every test using the real
    /// `WAFormTemplateRepositoryImpl` would read/write the *actual*
    /// developer machine's real Application Support folder — exactly the
    /// kind of real-filesystem test pollution `CONTRIBUTING.md` §5 already
    /// guards against for `UserDefaults` (`WAFormTemplateRepositoryImplTests`
    /// already uses a dedicated `UserDefaults(suiteName:)` per test for the
    /// identical reason). Tests pass a fresh temporary directory here;
    /// production code never passes anything, getting the real location.
    static func fileURLs(baseDirectory: URL? = nil) throws -> (mainFormURL: URL, continuationFormURL: URL) {
        let directory = try templateDirectory(baseDirectory: baseDirectory)
        return (
            mainFormURL: directory.appendingPathComponent("main-form.pdf"),
            continuationFormURL: directory.appendingPathComponent("continuation-form.pdf")
        )
    }

    private static func templateDirectory(baseDirectory: URL?) throws -> URL {
        let base = try baseDirectory ?? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("WAFormTemplates", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
