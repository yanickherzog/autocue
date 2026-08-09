import SwiftUI

/// A generic empty-state display — no knowledge of `Project`/`Setup`/`Cue` or any
/// other domain type, per CLAUDE.md's Design System rule. Feature code supplies its
/// own copy and, optionally, an action.
public struct EmptyStateView: View {
    private let systemImage: String
    private let title: String
    private let message: String?
    private let actionTitle: String?
    private let action: (() -> Void)?
    private let surface: Theme.Surface

    public init(
        systemImage: String,
        title: String,
        message: String? = nil,
        actionTitle: String? = nil,
        surface: Theme.Surface = .primary,
        action: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.surface = surface
        self.action = action
    }

    public var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(surface.foreground.opacity(0.5))

            Text(title)
                .font(Theme.Typography.font(.medium, size: 17))
                .foregroundStyle(surface.foreground)

            if let message {
                Text(message)
                    .font(Theme.Typography.font(.regular, size: 13))
                    .foregroundStyle(surface.foreground.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(SharpButtonStyle(emphasis: .primary, surface: surface))
                    .padding(.top, Theme.Spacing.xs)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(surface.background)
    }
}

#Preview("EmptyStateView — primary") {
    EmptyStateView(
        systemImage: "tray",
        title: "No Projects Yet",
        message: "Create a project to get started.",
        actionTitle: "New Project",
        surface: .primary,
        action: {}
    )
}

#Preview("EmptyStateView — reversed") {
    EmptyStateView(
        systemImage: "checkmark.seal",
        title: "Nothing to Review",
        message: "Add cues before exporting.",
        surface: .reversed
    )
}
