import ACCore
import Foundation

/// Backs the WA Film tab (`ROADMAP.md` D12/T12.4) — the fourth, always-
/// visible `ProjectSection`. Unlike the combined Review & Export destination
/// (three independently-built, independently-testable child ViewModels
/// composed by a deliberately thin `ReviewAndExportViewModel`), this screen
/// is backed by **one** ViewModel owning every piece of its state directly —
/// a real, deliberate departure from that precedent, not an oversight. See
/// `docs/DECISIONS.md` for the reasoning: unlike Review & Export's three
/// pieces (which genuinely don't share mutable state — `ExportViewModel`
/// reads `issues` as a plain parameter, nothing more), this screen's
/// template import action *is* the one thing every other piece of this
/// screen's state depends on (the preview, the validation issues, and the
/// export action all need the current template) — splitting template
/// ownership across multiple ViewModels would reintroduce exactly the
/// "same piece of state kept in sync by hand across multiple places"
/// problem `CLAUDE.md`'s Single Source of Truth section warns against.
///
/// **Live-subscribes to `ObserveProjectsUseCase.observeAll()` indefinitely**,
/// the same shape `ReviewViewModel`/`CueSheetPreviewViewModel` already
/// establish — this screen owns no working copy of `Setup`/`[Cue]` to
/// protect, so every structural edit made anywhere else in the app
/// republishes here live, with no manual refresh.
///
/// **No bookmark lifecycle, unlike this type's original D12/T12.4 design —
/// a deliberate simplification, not a missing feature.** The template is
/// now a private copy inside AutoCue's own sandbox container
/// (`WAFormTemplateReference`'s own doc comment, `docs/DECISIONS.md`), so
/// there's nothing that can go stale to refresh; `currentTemplate`/
/// `templateFileURLs` are simply read fresh at `load()` time.
@Observable
@MainActor
public final class WAFilmFormViewModel {
    public let projectID: Project.ID

    public private(set) var currentTemplate: WAFormTemplateReference?
    /// The template's real, ready-to-open file URLs — `nil` under the exact
    /// same condition `currentTemplate` is `nil`. Only `WAFormPreviewView`
    /// uses this (to draw the real template pages as its `Canvas`
    /// background); no security-scoped access bracketing is needed around
    /// them (`WAFormTemplateRepository.templateFileURLs()`'s own doc
    /// comment).
    public private(set) var templateFileURLs: (mainFormURL: URL, continuationFormURL: URL)?
    public private(set) var previewPages: [CueSheetPageLayout] = []
    public private(set) var issues: [WAFormValidationIssue] = []
    public private(set) var cues: [Cue] = []
    public private(set) var people: [Person] = []
    public private(set) var labels: [Label] = []
    public private(set) var projectNotFound = false
    /// Set when `computeWAFormLayoutUseCase`/`validateWAFormUseCase` throws —
    /// a real file-I/O failure reading the template's own private copy
    /// (rare — unlike the original bookmark-based design, nothing external
    /// can move or rename it; this now mainly covers a corrupted/unreadable
    /// file), distinct from `importErrorMessage`/`exportErrorMessage`
    /// below, which cover their own, separate user-triggered actions.
    public private(set) var templateAccessErrorMessage: String?

    public private(set) var isImporting = false
    public var importErrorMessage: String?

    public private(set) var isExporting = false
    public private(set) var progressMessage: String?
    public private(set) var progressFraction: Double?
    public private(set) var lastExportSucceeded = false
    public var exportErrorMessage: String?

    private let observeProjectsUseCase: ObserveProjectsUseCase
    private let waFormTemplateUseCase: WAFormTemplateUseCase
    private let computeWAFormLayoutUseCase: ComputeWAFormLayoutUseCase
    private let validateWAFormUseCase: ValidateWAFormUseCase
    private let exportWAFormUseCase: ExportWAFormUseCase
    private let shareValidationStrictness: ShareValidationStrictness

    private var latestProject: Project?

    public init(
        projectID: Project.ID,
        observeProjectsUseCase: ObserveProjectsUseCase,
        waFormTemplateUseCase: WAFormTemplateUseCase,
        computeWAFormLayoutUseCase: ComputeWAFormLayoutUseCase,
        validateWAFormUseCase: ValidateWAFormUseCase,
        exportWAFormUseCase: ExportWAFormUseCase,
        shareValidationStrictness: ShareValidationStrictness
    ) {
        self.projectID = projectID
        self.observeProjectsUseCase = observeProjectsUseCase
        self.waFormTemplateUseCase = waFormTemplateUseCase
        self.computeWAFormLayoutUseCase = computeWAFormLayoutUseCase
        self.validateWAFormUseCase = validateWAFormUseCase
        self.exportWAFormUseCase = exportWAFormUseCase
        self.shareValidationStrictness = shareValidationStrictness
    }

    /// Runs for the whole screen's lifetime (called once from the hosting
    /// View's `.task`), the same shape `ReviewViewModel.load()` already
    /// establishes.
    public func load() async {
        loadTemplate()
        for await projects in observeProjectsUseCase.observeAll() {
            guard let project = projects.first(where: { $0.id == projectID }) else {
                projectNotFound = true
                break
            }
            projectNotFound = false
            latestProject = project
            cues = project.cues
            people = project.people
            labels = project.labels
            recomputePreviewAndValidation(for: project)
        }
    }

    private func loadTemplate() {
        currentTemplate = waFormTemplateUseCase.currentTemplate()
        templateFileURLs = waFormTemplateUseCase.templateFileURLs()
    }

    private func recomputePreviewAndValidation(for project: Project) {
        guard currentTemplate != nil else {
            previewPages = []
            issues = []
            templateAccessErrorMessage = nil
            return
        }
        do {
            previewPages = try computeWAFormLayoutUseCase.compute(for: project)
            issues = try validateWAFormUseCase.validate(project)
            templateAccessErrorMessage = nil
        } catch {
            previewPages = []
            issues = []
            templateAccessErrorMessage = "Couldn't read the imported WA Film template: \(error.localizedDescription)"
        }
    }

    /// Imports a new template (first-time import or an explicit "Replace
    /// Template…" action — both the same operation; see
    /// `WAFormTemplateReference`'s own doc comment for why this is a single
    /// app-level resource with no separate "add" vs. "replace" distinction
    /// at the Repository layer). Recomputes the preview/validation
    /// immediately against `latestProject`, if already loaded, so a
    /// successful import is reflected without waiting for the next
    /// `observeAll()` emission (which may never come if nothing else
    /// changes the `Project` in the meantime).
    public func importTemplate(mainFormURL: URL, continuationFormURL: URL) async {
        isImporting = true
        importErrorMessage = nil
        defer { isImporting = false }
        do {
            let reference = try waFormTemplateUseCase.importTemplate(
                mainFormURL: mainFormURL,
                continuationFormURL: continuationFormURL
            )
            currentTemplate = reference
            templateFileURLs = waFormTemplateUseCase.templateFileURLs()
            if let latestProject {
                recomputePreviewAndValidation(for: latestProject)
            }
        } catch {
            importErrorMessage = "Couldn't import the WA Film template: \(error.localizedDescription)"
        }
    }

    public var canExport: Bool {
        ValidateWAFormUseCase.isExportAllowed(issues: issues, strictness: shareValidationStrictness)
    }

    public func export(to destination: URL) async {
        guard currentTemplate != nil else { return }
        guard canExport else {
            exportErrorMessage = "Resolve the outstanding issues above before exporting."
            return
        }

        isExporting = true
        lastExportSucceeded = false
        exportErrorMessage = nil
        progressMessage = nil
        progressFraction = nil
        defer { isExporting = false }

        do {
            for try await progress in exportWAFormUseCase.export(
                projectID: projectID,
                to: destination,
                shareValidationStrictness: shareValidationStrictness
            ) {
                if case let .progress(update) = progress {
                    progressFraction = update.fractionCompleted
                    progressMessage = update.message
                }
            }
            lastExportSucceeded = true
        } catch {
            exportErrorMessage = Self.message(for: error)
        }
    }

    private static func message(for error: Error) -> String {
        switch error {
        case let ExportWAFormUseCase.Failure.validationIssuesPresent(issues):
            "Export blocked — \(issues.count) outstanding issue\(issues.count == 1 ? "" : "s")."
        case is ProjectNotFoundError:
            "This project may have been deleted."
        default:
            "Export failed: \(error.localizedDescription)"
        }
    }
}
