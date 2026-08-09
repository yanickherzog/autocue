import SwiftUI

/// Renders both fixed surface styles side by side, per `ROADMAP.md` D5's
/// Acceptance Criteria — not "both appearances" in the system light/dark sense,
/// since these tokens don't adapt to that setting at all. See CLAUDE.md, "Visual
/// Language."
private struct ThemeSwatchSheet: View {
    var body: some View {
        HStack(spacing: 0) {
            SurfaceSwatch(surface: .primary)
            SurfaceSwatch(surface: .reversed)
        }
        .frame(width: 720, height: 480)
    }
}

private struct SurfaceSwatch: View {
    let surface: Theme.Surface

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(surface == .primary ? "Primary Surface" : "Reversed Surface")
                .font(Theme.Typography.font(.bold, size: 20))

            Group {
                Text("Space Grotesk Regular").font(Theme.Typography.font(.regular, size: 15))
                Text("Space Grotesk Medium").font(Theme.Typography.font(.medium, size: 15))
                Text("Space Grotesk Bold").font(Theme.Typography.font(.bold, size: 15))
            }

            Divider()
                .overlay(surface.foreground.opacity(0.3))

            if surface == .primary {
                Text("Ghost placeholder text")
                    .font(Theme.Typography.font(.regular, size: 15))
                    .foregroundStyle(Theme.Colors.ghostTextPrimary)
            }

            Rectangle()
                .fill(Theme.Colors.accent)
                .frame(height: 24)

            Button("Primary Action") {}
                .buttonStyle(SharpButtonStyle(emphasis: .primary, surface: surface))
            Button("Secondary Action") {}
                .buttonStyle(SharpButtonStyle(emphasis: .secondary, surface: surface))

            Spacer()
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(surface.foreground)
        .background(surface.background)
    }
}

#Preview("Theme Tokens") {
    ThemeSwatchSheet()
}
