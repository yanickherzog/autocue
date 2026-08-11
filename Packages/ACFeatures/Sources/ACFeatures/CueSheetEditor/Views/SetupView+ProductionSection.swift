import ACCore
import ACDesignSystem
import SwiftUI

/// `SetupView`'s "Production" section — project title, production type/
/// exploitation-type checkbox grids, production year, broadcast details
/// ("Sendedatum"), and the timecode start/frame-rate row. See `SetupView`'s
/// own doc comment for why this screen is split across files.
///
/// **Deliberately does not show `totalMusicRuntime`.** It's owned by
/// `UpdateCueUseCase`'s auto-recompute (SPEC.md §4.14) once D10 exists, and
/// belongs on Review & Export instead — shown once the cue sheet is actually
/// filled out, per the original product brief. The underlying field/
/// recompute logic is unchanged; only where it's displayed moves.
///
/// **Also hidden from this screen:** `subtitle` (kept in the domain model,
/// simply not shown or editable anywhere yet — no real requirement surfaced
/// it). `Setup.producer`/`.directorOrPrincipal` live in the Artists section
/// (`SetupView+CollaboratorsSection.swift`).
///
/// **`productionRuntime` ("Production Runtime") is shown here,
/// reversing an earlier same-Deliverable decision to remove it in favor of
/// Review & Export (D11, not built yet).** Realized during testing that it's
/// still needed on this screen, not only at export time — re-added as its
/// own field, side-by-side with Production Year, rather than left waiting
/// for a screen that doesn't exist yet. See `docs/DECISIONS.md`.
///
/// **`ExploitationTypePicker` lives here, not in the conditional Series &
/// Broadcast section.** An earlier reorder pass grouped it there by visual
/// proximity alone; SPEC.md §4.2.3 deliberately designed `exploitationTypes`
/// as independent of `productionTypes` ("a production can be both
/// `.featureFilm` and use more than one exploitation channel") — gating it
/// behind a series-type selection would make Cinema/TV/Festival/Other
/// unreachable for every non-series project. Placed directly after
/// `ProductionTypePicker`: both are "what kind of production is this"
/// checkbox grids, conceptually paired even though structurally independent.
///
/// **`Setup.broadcastDetails` is `[BroadcastDetails]`, not
/// `BroadcastDetails?`** — a later-round reversal of this field's original
/// single-instance scoping, once the Setup screen was actually in use and a
/// real need for multiple broadcasts surfaced. See `docs/DECISIONS.md`.
extension SetupView {
    var productionSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionHeader("Production")
            GhostTextField(
                placeholder: "Project Title",
                // `beitrag` (SPEC.md §4.2) is set to `Title`'s current value
                // on every edit, not independently editable — the field
                // itself has no UI anywhere on this screen. `Setup.updating`
                // already supports setting more than one field in a single
                // call, so this is one binding, not a second hidden write
                // path that could drift out of sync with Title.
                text: field({ $0.title }, { setup, newTitle in
                    setup.updating(title: newTitle, beitrag: .some(newTitle))
                })
            )
            checkboxGroupSubtitle("Genre")
            ProductionTypePicker(
                selection: immediateField({ $0.productionTypes }, { $0.updating(productionTypes: $1) }),
                otherDescription: field(
                    { $0.otherProductionTypeDescription ?? "" },
                    { $0.updating(otherProductionTypeDescription: .some($1.isEmpty ? nil : $1)) }
                )
            )
            checkboxGroupSubtitle("Verwertung")
            ExploitationTypePicker(
                selection: immediateField({ $0.exploitationTypes }, { $0.updating(exploitationTypes: $1) }),
                otherDescription: field(
                    { $0.otherExploitationTypeDescription ?? "" },
                    { $0.updating(otherExploitationTypeDescription: .some($1.isEmpty ? nil : $1)) }
                )
            )
            productionYearAndRuntimeRow
            broadcastDetailsSection
            timecodeStartAndFrameRateRow
        }
    }

    var productionYearAndRuntimeRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            productionYearField
                .frame(maxWidth: .infinity, alignment: .leading)
            productionRuntimeField
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A leading `Text("Production Year")` label, matching
    /// `productionRuntimeField`'s/`timecodeStartField`'s own "label beside
    /// the field, not above it" treatment exactly, for the same reason:
    /// `GhostIntField`'s own placeholder vanishes once a real value is
    /// typed, so a persistent external label is what keeps this field's
    /// purpose legible once it has a value. The placeholder itself is now a
    /// real example year ("2026"), not a restatement of the label — the
    /// label already says what the field is for; the placeholder's job is
    /// to show what a value here actually looks like, the same distinction
    /// `productionRuntimeField`'s "HH:MM:SS" placeholder already draws.
    var productionYearField: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text("Production Year")
                .foregroundStyle(Theme.Surface.primary.foreground)
            GhostIntField(
                placeholder: "2026",
                value: Binding(
                    get: { draft.productionYear == 0 ? nil : draft.productionYear },
                    set: { newValue in
                        draft = draft.updating(productionYear: newValue ?? 0)
                        viewModel.updateDebounced(draft)
                    }
                )
            )
        }
    }

    /// A leading `Text("Production Runtime")` label, matching
    /// `timecodeStartField`'s own "label beside the field, not above it"
    /// treatment exactly — same reasoning: `GhostTextField`'s own placeholder
    /// vanishes once a real value is typed, so a persistent external label is
    /// what keeps this field's purpose legible once it has a value.
    var productionRuntimeField: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text("Production Runtime")
                .foregroundStyle(Theme.Surface.primary.foreground)
            GhostTextField(placeholder: "HH:MM:SS", text: productionRuntimeTextBinding)
        }
    }

    /// Bridges `Setup.productionRuntime: MediaDuration` to `GhostTextField`'s
    /// `String` binding — `HH:MM:SS`, the same treatment `timecodeStartTextBinding`
    /// already establishes for `Timecode`, minus the frames component: this is
    /// a *length* (`MediaDuration`, SPEC.md §4.8), not a *position*, so there's
    /// no frame-accurate component to parse. Parses via a local `HH:MM:SS`
    /// splitter with the same "reject, don't commit" policy
    /// `timecodeStartTextBinding` already uses for invalid input — a bad
    /// keystroke leaves `productionRuntime` untouched rather than crashing or
    /// silently substituting a value.
    ///
    /// **`.zero` maps to `""`, not `"00:00:00"`.** `MediaDuration.formatted`
    /// always zero-pads, so binding it directly would show the literal text
    /// "00:00:00" on a brand-new `Project` (`CreateProjectUseCase`'s own
    /// honest not-yet-entered sentinel for this non-optional field) —
    /// real-looking text, never the ghost placeholder, since `GhostTextField`
    /// only shows its placeholder when the bound text is genuinely empty.
    /// The same `== zero-sentinel ? empty : formatted` mapping
    /// `productionYearField`'s own binding already uses for `productionYear
    /// == 0`, applied here for `MediaDuration.zero`. Clearing the field back
    /// to empty text writes `.zero` back explicitly, the same "empty commits
    /// the honest unset value" behavior, not left showing stale text.
    private var productionRuntimeTextBinding: Binding<String> {
        Binding(
            get: { draft.productionRuntime == .zero ? "" : draft.productionRuntime.formatted },
            set: { newText in
                let trimmed = newText.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else {
                    draft = draft.updating(productionRuntime: .zero)
                    viewModel.updateDebounced(draft)
                    return
                }
                guard let seconds = Self.parseHoursMinutesSeconds(trimmed) else { return }
                draft = draft.updating(productionRuntime: MediaDuration(seconds: seconds))
                viewModel.updateDebounced(draft)
            }
        )
    }

    /// `HH:MM:SS` → total seconds, or `nil` for anything malformed
    /// (wrong part count, non-numeric parts, or an out-of-range minutes/
    /// seconds component) — mirrors `parseTimecodeComponents`'s "reject
    /// outright, never guess" approach, just without a frame-rate-aware
    /// component initializer to delegate range-checking to.
    private static func parseHoursMinutesSeconds(_ text: String) -> Double? {
        let parts = text.split(separator: ":")
        guard parts.count == 3 else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == 3,
              numbers[0] >= 0, (0 ..< 60).contains(numbers[1]), (0 ..< 60).contains(numbers[2])
        else {
            return nil
        }
        return Double(numbers[0] * 3600 + numbers[1] * 60 + numbers[2])
    }

    // MARK: - Broadcast details ("Sendedatum")

    var broadcastDetailsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Toggle("Sendedatum", isOn: broadcastDetailsToggle)
                .toggleStyle(SharpCheckboxToggleStyle(surface: .primary))
                .foregroundStyle(Theme.Surface.primary.foreground)
            if hasBroadcastDetails {
                ForEach(Array(draft.broadcastDetails.indices), id: \.self) { index in
                    broadcastDetailsRow(at: index)
                }
                Button {
                    addBroadcastDetailsEntry()
                } label: {
                    Text("+").frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(SharpButtonStyle(emphasis: .secondary, surface: .primary))
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private func broadcastDetailsRow(at index: Int) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            GhostTextField(placeholder: "Sender", text: broadcastDetailsBroadcasterBinding(at: index))
            GhostTextField(placeholder: "Sendung", text: broadcastDetailsProgrammeNameBinding(at: index))
            GhostDateField(placeholder: "Datum", date: broadcastDetailsDateBinding(at: index))
            if draft.broadcastDetails.count > 1 {
                Button {
                    removeBroadcastDetailsEntry(at: index)
                } label: {
                    Text("✕").foregroundStyle(Theme.Surface.primary.foreground.opacity(0.6))
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
        }
    }

    private func broadcastDetailsBroadcasterBinding(at index: Int) -> Binding<String> {
        field(
            { Self.broadcastDetailsEntry($0, at: index)?.broadcaster ?? "" },
            { setup, newValue in
                Self.updatingBroadcastDetailsEntry(setup, at: index) {
                    $0.with(broadcaster: newValue.isEmpty ? nil : newValue)
                }
            }
        )
    }

    private func broadcastDetailsProgrammeNameBinding(at index: Int) -> Binding<String> {
        field(
            { Self.broadcastDetailsEntry($0, at: index)?.programmeName ?? "" },
            { setup, newValue in
                Self.updatingBroadcastDetailsEntry(setup, at: index) {
                    $0.with(programmeName: newValue.isEmpty ? nil : newValue)
                }
            }
        )
    }

    private func broadcastDetailsDateBinding(at index: Int) -> Binding<Date> {
        field(
            { Self.broadcastDetailsEntry($0, at: index)?.date ?? Date() },
            { setup, newValue in
                Self.updatingBroadcastDetailsEntry(setup, at: index) { $0.with(date: newValue) }
            }
        )
    }

    private static func broadcastDetailsEntry(_ setup: Setup, at index: Int) -> BroadcastDetails? {
        setup.broadcastDetails.indices.contains(index) ? setup.broadcastDetails[index] : nil
    }

    private static func updatingBroadcastDetailsEntry(
        _ setup: Setup,
        at index: Int,
        _ transform: (BroadcastDetails) -> BroadcastDetails
    ) -> Setup {
        guard setup.broadcastDetails.indices.contains(index) else { return setup }
        var entries = setup.broadcastDetails
        entries[index] = transform(entries[index])
        return setup.updating(broadcastDetails: entries)
    }

    private func addBroadcastDetailsEntry() {
        draft = draft.updating(broadcastDetails: draft.broadcastDetails + [BroadcastDetails()])
        Task { await viewModel.updateImmediately(draft) }
    }

    private func removeBroadcastDetailsEntry(at index: Int) {
        guard draft.broadcastDetails.indices.contains(index) else { return }
        var entries = draft.broadcastDetails
        entries.remove(at: index)
        draft = draft.updating(broadcastDetails: entries)
        Task { await viewModel.updateImmediately(draft) }
    }

    var broadcastDetailsToggle: Binding<Bool> {
        Binding(
            get: { hasBroadcastDetails },
            set: { isOn in
                hasBroadcastDetails = isOn
                draft = draft.updating(
                    broadcastDetails: isOn
                        ? (draft.broadcastDetails.isEmpty ? [BroadcastDetails()] : draft.broadcastDetails)
                        : []
                )
                Task { await viewModel.updateImmediately(draft) }
            }
        )
    }

    // MARK: - Timecode Start / Frame Rate

    var timecodeStartAndFrameRateRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            timecodeStartField
                .frame(maxWidth: .infinity, alignment: .leading)
            timecodeFrameRatePicker
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A leading `Text("Timecode Start")` label, matching `Picker`'s own
    /// built-in "label to the left of the control" treatment — the same
    /// `.foregroundStyle(Theme.Surface.primary.foreground)` modifier applied
    /// to `timecodeFrameRatePicker` below (SwiftUI applies that to a
    /// `Picker`'s label text on macOS's default style) is applied here to an
    /// explicit `Text`, since `GhostTextField`'s own placeholder alone
    /// vanishes once a real value is typed — unlike `Picker`'s persistent
    /// label, which never disappears once a selection is made.
    var timecodeStartField: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text("Timecode Start")
                .foregroundStyle(Theme.Surface.primary.foreground)
            GhostTextField(placeholder: "HH:MM:SS:FF", text: timecodeStartTextBinding)
        }
    }

    /// Bridges `Setup.timecodeStart: Timecode?` to `GhostTextField`'s
    /// `String` binding — `Timecode`'s own `formatted(at:)`/`init?(components:
    /// frameRate:)` (SPEC.md §4.9) do the real formatting/parsing, the same
    /// initializer D9/T9.3's cue-boundary text field will reuse. Invalid
    /// input (including malformed drop-frame timecodes, already rejected by
    /// `init?(components:frameRate:)` itself) is simply not committed — the
    /// field's displayed text stays whatever was typed until it either
    /// parses or is cleared, never a crash or a silently-substituted value.
    private var timecodeStartTextBinding: Binding<String> {
        Binding(
            get: { draft.timecodeStart?.formatted(at: draft.timecodeFrameRate) ?? "" },
            set: { newText in
                let trimmed = newText.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else {
                    draft = draft.updating(timecodeStart: .some(nil))
                    viewModel.updateDebounced(draft)
                    return
                }
                guard let components = Self.parseTimecodeComponents(trimmed),
                      let timecode = Timecode(components: components, frameRate: draft.timecodeFrameRate)
                else {
                    return
                }
                draft = draft.updating(timecodeStart: .some(timecode))
                viewModel.updateDebounced(draft)
            }
        )
    }

    private static func parseTimecodeComponents(_ text: String) -> TimecodeComponents? {
        let parts = text.split(whereSeparator: { $0 == ":" || $0 == ";" })
        guard parts.count == 4 else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == 4 else { return nil }
        return TimecodeComponents(hours: numbers[0], minutes: numbers[1], seconds: numbers[2], frames: numbers[3])
    }

    /// Timecode Frame Rate — defaults to `.fps25` at the `Setup` type level
    /// (SPEC.md §4.9), so a brand-new `Project`'s picker already shows "25
    /// fps" selected without any extra wiring here.
    var timecodeFrameRatePicker: some View {
        Picker(
            "Timecode Frame Rate",
            selection: immediateField({ $0.timecodeFrameRate }, { $0.updating(timecodeFrameRate: $1) })
        ) {
            Text("24 fps").tag(TimecodeFrameRate.fps24)
            Text("25 fps").tag(TimecodeFrameRate.fps25)
            Text("29.97 fps (Non-Drop)").tag(TimecodeFrameRate.fps29_97NonDrop)
            Text("29.97 fps (Drop)").tag(TimecodeFrameRate.fps29_97Drop)
            Text("30 fps").tag(TimecodeFrameRate.fps30)
        }
        .foregroundStyle(Theme.Surface.primary.foreground)
        .tint(Theme.Colors.accent)
    }
}

extension BroadcastDetails {
    func with(broadcaster: String?? = nil, programmeName: String?? = nil, date: Date? = nil) -> BroadcastDetails {
        BroadcastDetails(
            broadcaster: broadcaster ?? self.broadcaster,
            programmeName: programmeName ?? self.programmeName,
            date: date ?? self.date
        )
    }
}
