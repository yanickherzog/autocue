import Foundation

/// Thin wrapper around `WAFormTemplateRepository` (`ROADMAP.md` D12) — the
/// "small wrapping Use Case" `CLAUDE.md`'s Dependency Injection Pattern
/// requires so the WA Film tab's ViewModel calls a Use Case rather than
/// holding a Repository reference directly, consistent with
/// `CONTRIBUTING.md` §6's "ViewModels call Use Cases only." One Use Case
/// covering both import and lookup, not two — both act on the same single
/// app-level resource, the same "one Use Case, multiple related methods"
/// shape `ExportCueSheetUseCase` already establishes.
public struct WAFormTemplateUseCase: Sendable {
    private let waFormTemplateRepository: WAFormTemplateRepository

    public init(waFormTemplateRepository: WAFormTemplateRepository) {
        self.waFormTemplateRepository = waFormTemplateRepository
    }

    public func importTemplate(mainFormURL: URL, continuationFormURL: URL) throws -> WAFormTemplateReference {
        try waFormTemplateRepository.importTemplate(mainFormURL: mainFormURL, continuationFormURL: continuationFormURL)
    }

    public func currentTemplate() -> WAFormTemplateReference? {
        waFormTemplateRepository.currentTemplate()
    }
}
