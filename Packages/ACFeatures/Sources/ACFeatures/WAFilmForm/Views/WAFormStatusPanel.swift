import ACCore
import ACDesignSystem
import SwiftUI

/// The WA Film tab's left panel (`ROADMAP.md` D12/T12.4) — which template
/// files are imported, a "Replace Template…" action, and every outstanding
/// `WAFormValidationIssue`. Same reversed-surface visual shape `ReviewView`
/// (D11/T11.1) already establishes for the analogous Review & Export panel —
/// this screen's own validation summary, not a duplicate of that one.
public struct WAFormStatusPanel: View {
    @Bindable private var viewModel: WAFilmFormViewModel
    @State private var isPresentingReplaceSheet = false

    public init(viewModel: WAFilmFormViewModel) {
        self.viewModel = viewModel
    }

    private var messages: [String] {
        WAFormValidationMessageFormatter.messages(
            for: viewModel.issues,
            cues: viewModel.cues,
            people: viewModel.people,
            labels: viewModel.labels
        )
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                templateInfo
                Divider().overlay(Theme.Surface.reversed.foreground.opacity(0.2))
                header
                if let templateAccessErrorMessage = viewModel.templateAccessErrorMessage {
                    Text(templateAccessErrorMessage)
                        .font(Theme.Typography.font(.regular, size: 13))
                        .foregroundStyle(Theme.Surface.reversed.foreground)
                } else if messages.isEmpty {
                    readyMessage
                } else {
                    issuesList
                }
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.Surface.reversed.background)
        .sheet(isPresented: $isPresentingReplaceSheet) {
            WAFormImportPromptView(viewModel: viewModel, onImported: { isPresentingReplaceSheet = false })
        }
    }

    private var templateInfo: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("WA Film Template")
                .font(Theme.Typography.font(.medium, size: 15))
                .foregroundStyle(Theme.Surface.reversed.foreground)
            if let template = viewModel.currentTemplate {
                Text(template.mainFormFileName)
                    .font(Theme.Typography.font(.regular, size: 12))
                    .foregroundStyle(Theme.Surface.reversed.foreground.opacity(0.6))
                Text(template.continuationFormFileName)
                    .font(Theme.Typography.font(.regular, size: 12))
                    .foregroundStyle(Theme.Surface.reversed.foreground.opacity(0.6))
            }
            Button("Replace Template…") {
                isPresentingReplaceSheet = true
            }
            .buttonStyle(SharpButtonStyle(emphasis: .secondary, surface: .reversed))
            .padding(.top, Theme.Spacing.xs)
        }
    }

    private var headerTitle: String {
        guard !messages.isEmpty else { return "Ready to Export" }
        return "\(messages.count) Issue\(messages.count == 1 ? "" : "s") Found"
    }

    private var header: some View {
        Text(headerTitle)
            .font(Theme.Typography.font(.medium, size: 15))
            .foregroundStyle(Theme.Surface.reversed.foreground)
    }

    private var readyMessage: some View {
        Text("No outstanding issues — this production's data fits the WA Film form's requirements.")
            .font(Theme.Typography.font(.regular, size: 13))
            .foregroundStyle(Theme.Surface.reversed.foreground.opacity(0.6))
    }

    private var issuesList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                Text(message)
                    .font(Theme.Typography.font(.regular, size: 13))
                    .foregroundStyle(Theme.Surface.reversed.foreground)
            }
        }
    }
}
