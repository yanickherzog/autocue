import ACCore
import ACDesignSystem
import SwiftUI

/// `SetupView`'s "Production" section — title, subtitle, producer/director,
/// runtimes, production year/types, timecode frame rate, beitrag. See
/// `SetupView`'s own doc comment for why this screen is split across files.
extension SetupView {
    var productionSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionHeader("Production")
            GhostTextField(placeholder: "Title", text: field({ $0.title }, { $0.updating(title: $1) }))
            GhostTextField(
                placeholder: "Subtitle",
                text: field({ $0.subtitle ?? "" }, { $0.updating(subtitle: .some($1.isEmpty ? nil : $1)) })
            )
            partyFieldRow(title: "Producer", party: draft.producer, field: .producer)
            partyFieldRow(title: "Director / Principal", party: draft.directorOrPrincipal, field: .directorOrPrincipal)
            productionRuntimeField
            HStack {
                Text("Total Music Runtime")
                    .font(Theme.Typography.font(.regular, size: 13))
                    .foregroundStyle(Theme.Surface.primary.foreground.opacity(0.6))
                Spacer()
                Text(draft.totalMusicRuntime.formatted)
                    .font(Theme.Typography.font(.regular, size: 13))
                    .foregroundStyle(Theme.Surface.primary.foreground)
            }
            productionYearField
            ProductionTypePicker(
                selection: immediateField({ $0.productionTypes }, { $0.updating(productionTypes: $1) }),
                otherDescription: field(
                    { $0.otherProductionTypeDescription ?? "" },
                    { $0.updating(otherProductionTypeDescription: .some($1.isEmpty ? nil : $1)) }
                )
            )
            timecodeFrameRatePicker
            GhostTextField(
                placeholder: "Beitrag",
                text: field({ $0.beitrag ?? "" }, { $0.updating(beitrag: .some($1.isEmpty ? nil : $1)) })
            )
        }
    }

    var productionRuntimeField: some View {
        HStack {
            Text("Production Runtime (minutes)")
                .font(Theme.Typography.font(.regular, size: 13))
                .foregroundStyle(Theme.Surface.primary.foreground.opacity(0.6))
            Spacer()
            TextField(
                "",
                value: field(
                    { Int(($0.productionRuntime.seconds / 60).rounded()) },
                    { setup, minutes in
                        setup.updating(productionRuntime: MediaDuration(seconds: Double(minutes) * 60))
                    }
                ),
                format: .number
            )
            .multilineTextAlignment(.trailing)
            .textFieldStyle(.plain)
            .foregroundStyle(Theme.Surface.primary.foreground)
            .frame(width: 80)
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
