import ACCore
import ACDesignSystem
import SwiftUI

/// `SetupView`'s "Series & Broadcasts" section — series/episode context,
/// exploitation types ("Verwertung"), and broadcast details ("Sendedatum").
/// See `SetupView`'s own doc comment for why this screen is split across
/// files.
extension SetupView {
    var broadcastSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionHeader("Series & Broadcasts")
            GhostTextField(
                placeholder: "Series Title",
                text: field({ $0.seriesTitle ?? "" }, { $0.updating(seriesTitle: .some($1.isEmpty ? nil : $1)) })
            )
            HStack(spacing: Theme.Spacing.sm) {
                optionalIntField(
                    placeholder: "Season",
                    get: { $0.seasonNumber },
                    set: { $0.updating(seasonNumber: .some($1)) }
                )
                optionalIntField(
                    placeholder: "Episode",
                    get: { $0.episodeNumber },
                    set: { $0.updating(episodeNumber: .some($1)) }
                )
            }
            GhostTextField(
                placeholder: "Episode Title",
                text: field({ $0.episodeTitle ?? "" }, { $0.updating(episodeTitle: .some($1.isEmpty ? nil : $1)) })
            )
            HStack(spacing: Theme.Spacing.sm) {
                GhostTextField(
                    placeholder: "Production Country",
                    text: field(
                        { $0.productionCountry ?? "" },
                        { $0.updating(productionCountry: .some($1.isEmpty ? nil : $1)) }
                    )
                )
                GhostTextField(
                    placeholder: "Language",
                    text: field({ $0.language ?? "" }, { $0.updating(language: .some($1.isEmpty ? nil : $1)) })
                )
            }
            GhostTextField(
                placeholder: "Known or Future Broadcasts",
                text: field(
                    { $0.knownOrFutureBroadcasts ?? "" },
                    { $0.updating(knownOrFutureBroadcasts: .some($1.isEmpty ? nil : $1)) }
                )
            )
            ExploitationTypePicker(
                selection: immediateField({ $0.exploitationTypes }, { $0.updating(exploitationTypes: $1) }),
                otherDescription: field(
                    { $0.otherExploitationTypeDescription ?? "" },
                    { $0.updating(otherExploitationTypeDescription: .some($1.isEmpty ? nil : $1)) }
                )
            )
            broadcastDetailsFields
        }
    }

    func optionalIntField(
        placeholder: String,
        get: @escaping (Setup) -> Int?,
        set: @escaping (Setup, Int) -> Setup
    ) -> some View {
        TextField(
            placeholder,
            value: field(
                { get($0) ?? 0 },
                { setup, newValue in set(setup, newValue) }
            ),
            format: .number.grouping(.never)
        )
        .textFieldStyle(.plain)
        .foregroundStyle(Theme.Surface.primary.foreground)
        .padding(Theme.Spacing.sm)
        .overlay(Rectangle().strokeBorder(Theme.Surface.primary.foreground.opacity(0.3), lineWidth: 1))
    }

    var broadcastDetailsFields: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Toggle("Sendedatum", isOn: broadcastDetailsToggle)
                .toggleStyle(.checkbox)
                .foregroundStyle(Theme.Surface.primary.foreground)
            if hasBroadcastDetails {
                GhostTextField(
                    placeholder: "Sender",
                    text: field(
                        { $0.broadcastDetails?.broadcaster ?? "" },
                        { setup, value in
                            setup.updating(broadcastDetails: .some(
                                (setup.broadcastDetails ?? BroadcastDetails())
                                    .with(broadcaster: value.isEmpty ? nil : value)
                            ))
                        }
                    )
                )
                GhostTextField(
                    placeholder: "Sendung",
                    text: field(
                        { $0.broadcastDetails?.programmeName ?? "" },
                        { setup, value in
                            setup.updating(broadcastDetails: .some(
                                (setup.broadcastDetails ?? BroadcastDetails())
                                    .with(programmeName: value.isEmpty ? nil : value)
                            ))
                        }
                    )
                )
                DatePicker(
                    "Datum der Sendung",
                    selection: field(
                        { $0.broadcastDetails?.date ?? Date() },
                        { setup, value in
                            setup.updating(broadcastDetails: .some(
                                (setup.broadcastDetails ?? BroadcastDetails()).with(date: value)
                            ))
                        }
                    ),
                    displayedComponents: .date
                )
                .datePickerStyle(.field)
                .foregroundStyle(Theme.Surface.primary.foreground)
            }
        }
    }

    var broadcastDetailsToggle: Binding<Bool> {
        Binding(
            get: { hasBroadcastDetails },
            set: { isOn in
                hasBroadcastDetails = isOn
                draft = draft.updating(broadcastDetails: .some(isOn ? BroadcastDetails() : nil))
                Task { await viewModel.updateImmediately(draft) }
            }
        )
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
