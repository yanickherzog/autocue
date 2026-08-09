import SwiftUI

/// A generic progress indicator for a long-running operation. Takes no `ACCore`
/// type — `fractionCompleted`/`message` are plain values a Feature-layer mapper
/// derives from `OperationProgress<T>` at the point a screen renders it, per
/// CLAUDE.md's Design System rule and the same local-adapter pattern established
/// for `WaveformDisplayData`/`CueTableView`'s row protocol.
public struct ProgressBanner: View {
    private let message: String
    /// `nil` renders an indeterminate spinner; `0.0...1.0` renders a determinate bar.
    private let fractionCompleted: Double?
    private let surface: Theme.Surface
    private let onCancel: (() -> Void)?

    public init(
        message: String,
        fractionCompleted: Double? = nil,
        surface: Theme.Surface = .primary,
        onCancel: (() -> Void)? = nil
    ) {
        self.message = message
        self.fractionCompleted = fractionCompleted
        self.surface = surface
        self.onCancel = onCancel
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Group {
                if let fractionCompleted {
                    ProgressView(value: fractionCompleted)
                } else {
                    ProgressView()
                }
            }
            .tint(Theme.Colors.accent)
            .frame(width: 120)

            Text(message)
                .font(Theme.Typography.font(.regular, size: 13))
                .foregroundStyle(surface.foreground)

            Spacer(minLength: Theme.Spacing.sm)

            if let onCancel {
                Button("Cancel", action: onCancel)
                    .buttonStyle(SharpButtonStyle(emphasis: .secondary, surface: surface))
            }
        }
        .padding(Theme.Spacing.sm)
        .background(surface.background)
        .overlay(
            Rectangle().strokeBorder(surface.foreground.opacity(0.2), lineWidth: 1)
        )
    }
}

#Preview("ProgressBanner — determinate") {
    ProgressBanner(message: "Importing audio…", fractionCompleted: 0.42, onCancel: {})
        .padding(Theme.Spacing.lg)
        .background(Theme.Surface.primary.background)
}

#Preview("ProgressBanner — indeterminate, reversed") {
    ProgressBanner(message: "Preparing export…", surface: .reversed)
        .padding(Theme.Spacing.lg)
        .background(Theme.Surface.reversed.background)
}
