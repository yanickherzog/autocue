import ACCore
import ACDesignSystem
import SwiftUI

/// `SetupView`'s "Series & Broadcast" section — series/episode context and
/// general broadcast notes. See `SetupView`'s own doc comment for why this
/// screen is split across files.
///
/// **Only visible when a series-type `ProductionType` is selected** —
/// `SetupView.body` gates this section on `draft.productionTypes.contains
/// (.series)`, hidden entirely otherwise. Season/Episode/Episode Title are
/// genuinely series-specific; nothing here is meaningful for a non-series
/// production.
///
/// **`ExploitationTypePicker` ("Verwertung") and `broadcastDetailsSection`
/// ("Sendedatum") deliberately do *not* live here**, despite both once
/// having been grouped under a "broadcasts" heading with this section's
/// other fields. SPEC.md §4.2.3 designed `exploitationTypes` as independent
/// of `productionTypes` — a `.featureFilm` can just as legitimately use
/// multiple exploitation channels as a `.series` can — so gating it behind
/// series-type selection would make Cinema/TV/Festival/Other unreachable for
/// the majority of non-series projects. Both moved to the always-visible
/// `SetupView+ProductionSection.swift` instead. See `docs/DECISIONS.md`/
/// `ROADMAP.md` D7's later-round narrative for the full reasoning.
///
/// **Season/Episode use `GhostIntField`** — the same ghost-placeholder
/// treatment `seriesTitle`/`episodeTitle` already get via `GhostTextField`,
/// with no numeric stepper and no default value (an earlier version bound
/// these through a `nil`-coerced-to-`0` numeric `TextField`, which silently
/// showed a literal "0" instead of ever looking empty — see `GhostIntField`'s
/// own doc comment).
///
/// **Multiple Episode Titles when Episode count is more than one: a real,
/// pre-existing app-internal-only gap, not a SUISA-form question — not
/// addressed by this reorder.** `seasonNumber`/`episodeNumber`/`episodeTitle`
/// (SPEC.md §4.2) are all explicitly "not on the [SUISA] form" — the
/// physical WA Film declaration has no episode concept at all, so there's no
/// authoritative "primary title only" answer to look up there either way.
/// The actual reason there's no way to list more than one Episode Title is
/// that `episodeNumber`/`episodeTitle` are both singular (`Int?`/`String?`)
/// — this schema has never supported more than one episode per `Setup`/
/// `Project`. The only existing way to declare multiple episodes is one
/// `Project` per episode, matching this app's existing one-production-per-
/// window model (`CLAUDE.md`, "Document & Window Model"). Whether to support
/// a multi-episode batch within a single `Setup` is a product decision, not
/// a compliance one — left open, not decided here.
extension SetupView {
    var seriesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionHeader("Series & Broadcast")
            GhostTextField(
                placeholder: "Series Title",
                text: field({ $0.seriesTitle ?? "" }, { $0.updating(seriesTitle: .some($1.isEmpty ? nil : $1)) })
            )
            HStack(spacing: Theme.Spacing.sm) {
                GhostIntField(
                    placeholder: "Season",
                    value: field({ $0.seasonNumber }, { $0.updating(seasonNumber: .some($1)) })
                )
                GhostIntField(
                    placeholder: "Episode",
                    value: field({ $0.episodeNumber }, { $0.updating(episodeNumber: .some($1)) })
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
        }
    }
}
