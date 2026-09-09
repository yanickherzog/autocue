import SwiftUI

/// A minimal, fully-opaque, custom-drawn horizontal slider — built
/// specifically for `WaveformView`'s vertical-zoom control, not a
/// general-purpose replacement for SwiftUI's `Slider` (no second caller
/// exists yet; `CLAUDE.md` rule 7).
///
/// **Why this exists instead of the stock `Slider`:** confirmed via a real,
/// on-screen, window-server-composited capture (not assumed) — AppKit's
/// stock `Slider` knob renders translucent (~50% alpha) with no opaque
/// backing of its own, letting whatever's drawn underneath (here,
/// `WaveformView`'s waveform trace/cue-spans/marker lines) show through it.
/// Giving it an explicit `.background(Rectangle()...)` stopped the
/// bleed-through but introduced its own unwanted visible rectangle. Neither
/// problem exists here: every shape below is a solid, fully opaque fill
/// sized to its own bounds — no bounding-box background layer at all, so
/// there's nothing to show through and nothing extra to see beyond the
/// track/thumb themselves. Same "stock AppKit-backed control's rendering
/// can't be fully controlled from SwiftUI, so draw it ourselves" shape this
/// project already established for `SharpButtonStyle`/
/// `SharpCheckboxToggleStyle`. See `docs/DECISIONS.md`.
struct VerticalScaleSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>

    private static let trackHeight: CGFloat = 4
    private static let thumbDiameter: CGFloat = 16

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let fraction = normalizedFraction
            let thumbX = fraction * width

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Theme.Colors.white)
                    .frame(width: width, height: Self.trackHeight)
                Rectangle()
                    .fill(Theme.Colors.accent)
                    .frame(width: thumbX, height: Self.trackHeight)
                Circle()
                    .fill(Theme.Colors.white)
                    .frame(width: Self.thumbDiameter, height: Self.thumbDiameter)
                    .offset(x: thumbX - Self.thumbDiameter / 2)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        value = Self.value(atX: drag.location.x, width: width, range: range)
                    }
            )
        }
        .frame(height: Self.thumbDiameter)
        .accessibilityElement()
        .accessibilityLabel(Text("Vertical zoom"))
        .accessibilityValue(Text(String(format: "%.2f", value)))
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 20
            switch direction {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: break
            }
        }
    }

    private var normalizedFraction: Double {
        guard range.upperBound > range.lowerBound else { return 0 }
        return ((value - range.lowerBound) / (range.upperBound - range.lowerBound)).clamped(to: 0 ... 1)
    }

    private static func value(atX xPosition: CGFloat, width: CGFloat, range: ClosedRange<Double>) -> Double {
        guard width > 0 else { return range.lowerBound }
        let fraction = Double(xPosition / width).clamped(to: 0 ... 1)
        return range.lowerBound + fraction * (range.upperBound - range.lowerBound)
    }
}

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

#Preview("VerticalScaleSlider") {
    VerticalScaleSlider(value: .constant(1.5), range: 0.25 ... 4)
        .frame(width: 100)
        .padding()
        .background(Theme.Surface.reversed.background)
}
