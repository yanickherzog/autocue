import ACCore
import ACDesignSystem
import SwiftUI

/// The Review section's root content (`ROADMAP.md` D11/T11.1) — every
/// outstanding validation issue, plus `Setup.totalMusicRuntime` (SPEC.md
/// §4.14), displayed on the reversed surface (`CLAUDE.md`'s Visual
/// Language: "Review & Export uses the reversed surface"). Composed into
/// the actual combined Review & Export screen at T11.5, alongside export
/// controls — not wired into navigation on its own yet.
///
/// Receives its ViewModel as a plain initializer parameter, per `CLAUDE.md`'s
/// Dependency Injection Pattern — never constructs or looks it up itself.
public struct ReviewView: View {
    @Bindable var viewModel: ReviewViewModel

    public init(viewModel: ReviewViewModel) {
        _viewModel = Bindable(viewModel)
    }

    private var messages: [String] {
        ReviewIssueMessageFormatter.messages(
            for: viewModel.issues,
            cues: viewModel.cues,
            people: viewModel.people,
            labels: viewModel.labels
        )
    }

    public var body: some View {
        Group {
            if viewModel.projectNotFound {
                EmptyStateView(
                    systemImage: "exclamationmark.triangle",
                    title: "Project Not Found",
                    message: "This project may have been deleted.",
                    surface: .reversed
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        header
                        if messages.isEmpty {
                            readyMessage
                        } else {
                            issuesList
                        }
                    }
                    .padding(Theme.Spacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Surface.reversed.background)
        // See FixedAppearanceModifier's doc comment — same reasoning
        // SetupView already applies for the primary surface, here for the
        // reversed one.
        .fixedAppearance(for: .reversed)
        .task {
            await viewModel.load()
        }
    }

    private var headerTitle: String {
        guard !messages.isEmpty else { return "Ready to Export" }
        return "\(messages.count) Issue\(messages.count == 1 ? "" : "s") Found"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(headerTitle)
                .font(Theme.Typography.font(.medium, size: 17))
                .foregroundStyle(Theme.Surface.reversed.foreground)
            Text("Total Music Runtime: \(viewModel.totalMusicRuntime.formatted)")
                .font(Theme.Typography.font(.regular, size: 13))
                .foregroundStyle(Theme.Surface.reversed.foreground.opacity(0.6))
        }
    }

    private var readyMessage: some View {
        Text("No outstanding issues — every required field is filled in and every cue's shares sum correctly.")
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
