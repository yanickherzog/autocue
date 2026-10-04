import ACDesignSystem
import SwiftUI
import UniformTypeIdentifiers

/// The WA Film tab's template-import flow (`ROADMAP.md` D12/T12.4) — used
/// both as the tab's own full-screen empty state (no template imported yet)
/// and, hosted in a sheet, as the "Replace Template…" action once a template
/// already exists (`WAFormStatusPanel`).
///
/// **One combined picker, selecting both files at once — auto-detects which
/// is the main form and which is the continuation form.** A real, deliberate
/// reversal of this View's original two-separate-pickers design
/// (`docs/DECISIONS.md`, D12/T12.4): the project owner's explicit
/// requirement was a fully automatic experience, and since the template is
/// a fixed, known, one-time import, there's no real reason to make the user
/// identify which file is which by hand every time — `WAFormTemplateClassifier`
/// does that from each file's own real content (and, as a fallback, its page
/// count) instead.
public struct WAFormImportPromptView: View {
    @Bindable private var viewModel: WAFilmFormViewModel
    let onImported: (() -> Void)?

    @State private var isPresentingImporter = false
    @State private var isClassifying = false
    @State private var classificationErrorMessage: String?

    public init(viewModel: WAFilmFormViewModel, onImported: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.onImported = onImported
    }

    public var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "doc.text")
                .font(.system(size: 40))
                .foregroundStyle(Theme.Surface.primary.foreground.opacity(0.5))

            Text("Import WA Film Template")
                .font(Theme.Typography.font(.medium, size: 17))
                .foregroundStyle(Theme.Surface.primary.foreground)

            Text(
                "AutoCue never bundles SUISA's own form — select your own legitimately-obtained copies of the " +
                    "WA Film main form and continuation form (WA Film II) PDFs, in one step. AutoCue identifies " +
                    "which is which automatically. Your production's data is drawn on top of your own imported " +
                    "pages; the files themselves are never modified."
            )
            .font(Theme.Typography.font(.regular, size: 13))
            .foregroundStyle(Theme.Surface.primary.foreground.opacity(0.6))
            .multilineTextAlignment(.center)
            .frame(maxWidth: 420)

            if viewModel.isImporting || isClassifying {
                ProgressBanner(message: isClassifying ? "Identifying files…" : "Importing…")
            } else {
                Button("Choose Files…") {
                    isPresentingImporter = true
                }
                .buttonStyle(SharpButtonStyle(emphasis: .primary, surface: .primary))
            }

            if let message = classificationErrorMessage ?? viewModel.importErrorMessage {
                Text(message)
                    .font(Theme.Typography.font(.regular, size: 12))
                    .foregroundStyle(Theme.Colors.accent)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Surface.primary.background)
        .fileImporter(
            isPresented: $isPresentingImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true,
            onCompletion: handleSelection
        )
    }

    private func handleSelection(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard urls.count == 2 else {
                classificationErrorMessage = "Select exactly two PDF files — the WA Film main form and " +
                    "continuation form."
                return
            }
            classificationErrorMessage = nil
            Task { await classifyAndImport(urls) }
        case .failure:
            // The user cancelled the picker — no real failure, no state
            // change needed, same as `AudioImportView`'s own handling.
            break
        }
    }

    /// Classifies both files, then imports only once both are confidently
    /// and distinctly identified — never a partial or guessed import.
    private func classifyAndImport(_ urls: [URL]) async {
        isClassifying = true
        defer { isClassifying = false }

        var mainFormURL: URL?
        var continuationFormURL: URL?
        var unrecognized: [String] = []

        for url in urls {
            let accessGranted = url.startAccessingSecurityScopedResource()
            defer {
                if accessGranted {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            switch WAFormTemplateClassifier.classify(fileAt: url) {
            case .mainForm:
                if mainFormURL != nil {
                    classificationErrorMessage = "Both selected files look like the main form — select one " +
                        "main form and one continuation form."
                    return
                }
                mainFormURL = url
            case .continuationForm:
                if continuationFormURL != nil {
                    classificationErrorMessage = "Both selected files look like the continuation form — select " +
                        "one main form and one continuation form."
                    return
                }
                continuationFormURL = url
            case nil:
                unrecognized.append(url.lastPathComponent)
            }
        }

        guard unrecognized.isEmpty else {
            let names = unrecognized.joined(separator: ", ")
            classificationErrorMessage = "Couldn't identify \(names) as a WA Film main or continuation form."
            return
        }
        guard let mainFormURL, let continuationFormURL else {
            classificationErrorMessage = "Select one main form and one continuation form PDF."
            return
        }

        await viewModel.importTemplate(mainFormURL: mainFormURL, continuationFormURL: continuationFormURL)
        if viewModel.currentTemplate != nil {
            onImported?()
        }
    }
}
