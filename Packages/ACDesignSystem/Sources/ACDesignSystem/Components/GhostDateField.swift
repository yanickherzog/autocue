import SwiftUI

/// A date display/entry control styled consistently with `GhostTextField`/
/// `GhostIntField` — no domain knowledge, just `Date`/closures.
///
/// **Why this exists instead of a plain `DatePicker`.** SwiftUI's
/// `DatePicker` (in any style — `.field`, `.compact`, etc.) is rendered by
/// AppKit's native `NSDatePicker` on macOS, which never adopts this app's
/// custom Space Grotesk typography (`CLAUDE.md`'s Visual Language) — its
/// digits render in the system font, at the system's own letter-spacing,
/// visibly inconsistent with every surrounding piece of text on the Setup
/// screen. This is the same class of problem `SharpButtonStyle` exists to
/// solve for buttons (a native control that needs a real custom
/// presentation, not just a color/font override that AppKit ignores):
/// `.foregroundStyle()`/`.font()` applied directly to a `DatePicker` doesn't
/// reach its internal text rendering.
///
/// **The fix: draw the date ourselves.** The persistent, always-visible
/// piece is a real, directly-typeable `TextField` — full control over font
/// (Space Grotesk, `.monospacedDigit()` so day/month/year digits stay a
/// consistent width as they change) and color, styled identically to
/// `GhostTextField`'s bordered-box recipe. A trailing calendar-icon button
/// reveals a real `DatePicker` inside a `.popover` for click-based
/// selection instead — the native picker still does the real date-picking
/// work (calendar math, locale-aware layout), it just never has to look
/// visually consistent with the rest of the screen, since it's only ever
/// shown transiently, not as a permanent piece of chrome. Typing and
/// clicking both write the same underlying `Date` — neither is the "real"
/// path, they're two entry points to the same value.
public struct GhostDateField: View {
    /// Unlike `GhostTextField`'s placeholder (which vanishes the moment
    /// there's a real value), a `Date` is never genuinely "empty" — there's
    /// no natural state in which ghost placeholder text alone would ever be
    /// visible. So this renders as a small, persistently-visible caption
    /// leading the date box instead — styled identically to `SetupView`'s
    /// "Timecode Start" label (a plain, undecorated `Text` at full-opacity
    /// `surface.foreground`, in an `HStack` beside the field, not above it)
    /// so every persistent field-label treatment on the Setup screen reads
    /// as genuinely the same, not just similar. `nil` (default) omits the
    /// caption entirely, for a call site that doesn't need one.
    private let placeholder: String?
    @Binding private var date: Date
    private let surface: Theme.Surface

    public init(placeholder: String? = nil, date: Binding<Date>, surface: Theme.Surface = .primary) {
        self.placeholder = placeholder
        _date = date
        self.surface = surface
    }

    @State private var isShowingPicker = false

    /// `dd.MM.yyyy`, not a locale-driven `.medium`/`.short` style — a fixed
    /// format is what keeps digit positions stable (so `.monospacedDigit()`
    /// actually reads as aligned) regardless of the host machine's region
    /// settings, matching the Swiss/European date convention this app's
    /// target market (`CLAUDE.md`, SUISA) already assumes elsewhere. Reused
    /// for both display and typed-entry parsing — one format, not two, so
    /// what's shown is always exactly what you'd need to type to reproduce
    /// it.
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter
    }()

    public var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let placeholder {
                Text(placeholder)
                    .foregroundStyle(surface.foreground)
            }
            HStack(spacing: Theme.Spacing.xs) {
                TextField("", text: dateTextBinding)
                    .textFieldStyle(.plain)
                    .font(Theme.Typography.font(.regular, size: 13).monospacedDigit())
                    .foregroundStyle(surface.foreground)
                Button {
                    isShowingPicker = true
                } label: {
                    Image(systemName: "calendar")
                        .foregroundStyle(surface.foreground.opacity(0.6))
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .popover(isPresented: $isShowingPicker) {
                    DatePicker("", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .tint(Theme.Colors.accent)
                        .padding(Theme.Spacing.md)
                }
            }
            .padding(Theme.Spacing.sm)
            .overlay(Rectangle().strokeBorder(surface.foreground.opacity(0.3), lineWidth: 1))
        }
    }

    /// Bridges `date: Binding<Date>` to the `TextField`'s `String` binding —
    /// `Date` is never actually "unset" the way `Setup.timecodeStart:
    /// Timecode?` can be, so there's no clear-to-nil case to handle here,
    /// unlike `SetupView`'s own `timecodeStartTextBinding`, which this
    /// mirrors otherwise: `get` always re-formats the current committed
    /// `date`, so an invalid in-progress edit reverts to the last valid
    /// value the moment the field loses focus (nothing was ever written to
    /// `date` for it to revert *from*). `set` only writes `date` on a fully
    /// successful parse — **invalid or partial input is rejected outright,
    /// never committed** (not "reject with an alert," just silently not
    /// applied, the same choice already made for Timecode Start) — so a
    /// bad keystroke can never leave `date` holding garbage, and the field
    /// never crashes or silently substitutes an unintended value.
    private var dateTextBinding: Binding<String> {
        Binding(
            get: { Self.formatter.string(from: date) },
            set: { newText in
                let trimmed = newText.trimmingCharacters(in: .whitespaces)
                guard let parsed = Self.formatter.date(from: trimmed) else { return }
                date = parsed
            }
        )
    }
}

#Preview("GhostDateField") {
    struct PreviewHost: View {
        @State private var date = Date()
        var body: some View {
            GhostDateField(placeholder: "Datum", date: $date)
                .padding(Theme.Spacing.lg)
                .background(Theme.Surface.primary.background)
                .frame(width: 240)
        }
    }
    return PreviewHost()
}
