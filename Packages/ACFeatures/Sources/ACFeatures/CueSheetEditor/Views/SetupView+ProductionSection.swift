import ACCore
import ACDesignSystem
import SwiftUI

/// `SetupView`'s "Production" section — title, production year/types,
/// timecode frame rate. See `SetupView`'s own doc comment for why this
/// screen is split across files.
///
/// **Deliberately does not show `totalMusicRuntime`.** It's owned by
/// `UpdateCueUseCase`'s auto-recompute (SPEC.md §4.14) once D10 exists, and
/// belongs on Review & Export instead — shown once the cue sheet is actually
/// filled out, per the original product brief. The underlying field/
/// recompute logic is unchanged; only where it's displayed moves.
///
/// **Also hidden from this screen, later round (`ROADMAP.md` D7):**
/// `subtitle` (kept in the domain model, simply not shown or editable
/// anywhere yet — no real requirement surfaced it); `productionRuntime`
/// (moving to Review & Export, D11 — not built there yet either, so there is
/// currently no UI for it anywhere, deliberately, matching "not built now");
/// `beitrag` (kept in the domain model, but no longer independently
/// editable — see the `Title` field's own binding below, which sets it
/// automatically). `Setup.producer`/`.directorOrPrincipal` moved to the
/// Artists section (`SetupView+CollaboratorsSection.swift`), after Label —
/// see that file's doc comment for why they stayed single-select `Setup`
/// fields rather than becoming roster buckets.
extension SetupView {
    var productionSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionHeader("Production")
            GhostTextField(
                placeholder: "Title",
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
            productionYearField
            ProductionTypePicker(
                selection: immediateField({ $0.productionTypes }, { $0.updating(productionTypes: $1) }),
                otherDescription: field(
                    { $0.otherProductionTypeDescription ?? "" },
                    { $0.updating(otherProductionTypeDescription: .some($1.isEmpty ? nil : $1)) }
                )
            )
            timecodeFrameRatePicker
        }
    }

    var productionYearField: some View {
        HStack {
            Text("Production Year")
                .font(Theme.Typography.font(.regular, size: 13))
                .foregroundStyle(Theme.Surface.primary.foreground.opacity(0.6))
            Spacer()
            TextField(
                "",
                value: field({ $0.productionYear }, { $0.updating(productionYear: $1) }),
                format: .number.grouping(.never)
            )
            .multilineTextAlignment(.trailing)
            .textFieldStyle(.plain)
            .foregroundStyle(Theme.Surface.primary.foreground)
            .frame(width: 80)
        }
    }

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
    }
}
