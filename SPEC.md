# AutoCue — Application Specification

Status: data model and compliance target finalized. No UI or business logic implemented yet.

## 0. Platform Requirements

Minimum supported macOS version: **14.0 (Sonoma)** — the floor required by `SwiftData` and `@Observable`, both already-committed architectural choices. Full reasoning and enforcement points: `CLAUDE.md`, "Deployment Target."

## 1. Purpose

AutoCue is a native macOS application that generates Swiss film/TV cue sheets from WAV audio files. It analyzes a production's audio (embedded markers plus signal analysis) to identify the musical works it contains, and produces a cue sheet compliant with the format SUISA (Swiss authors'/publishers' rights society) requires for royalty distribution, exportable as PDF and XLSX.

## 2. Compliance Target

### 2.1 SUISA — "Declaration of musical works for films and audiovisual productions" (WA Film)

This is the primary, binding target format. It is SUISA's own paper/PDF form (form codes `WA Film 2011-01` main form + `WA Film II 2011-01` additional-works continuation, obtained directly from suisa.ch), submitted to SUISA's Film Department to report the musical works contained in a production and how performance/broadcast and mechanical rights are split between right-holders.

Structurally, this form is **not** a US-style (ASCAP/BMI) scene-by-scene cue log with usage categories (Background Instrumental, Visual Vocal, Main Title, etc.) and in/out timecodes. It is a **rights-accounting declaration**: for each musical work used in the production, it records the work's title, duration of use, and every right-holder's role and percentage share of performance/broadcast rights and mechanical rights. AutoCue's data model follows this shape. Do not import US cue-sheet conventions into required fields.

The main form holds 5 musical works per page and paginates with a 4-per-page continuation sheet ("Additional works") beyond that — this is an export/layout concern, not a data-model concern; the domain model has no fixed limit on the number of Cues per Project.

### 2.2 SWISSPERFORM

SWISSPERFORM (Swiss neighboring-rights society for performers and producers) does **not** have an equivalent per-production cue-sheet document. Its audiovisual-participation reporting is performer-centric and self-service: each performer registers their own participation (film/episode title, series/season, director, production country/year, function/role, shooting days or takes, role weighting) directly through SWISSPERFORM's online portal, not through a document the production company fills in per-production the way SUISA's WA Film form works.

Consequently, AutoCue does not attempt to generate a "SWISSPERFORM cue sheet" — no such artifact exists in the same shape as SUISA's. What it does instead: the `Person` model carries an optional `swissPerformNumber`, `Setup` carries the production-identity fields (series/season, director, country, language) that a performer would need when self-registering, and — as of `ROADMAP.md` D7's planning — a `Cue`'s right-holders can now carry a `.performer` role (§4.4) alongside composer/author/arranger/publisher, informational only and excluded from both share sums and the PDF export. All three are the same story: data AutoCue already collects can be reused/exported as reference information for SWISSPERFORM registration, without AutoCue claiming to produce an official SWISSPERFORM filing. Adding `.performer` doesn't change that conclusion — it only grows the list of data that supports it.

### 2.3 Revalidation checkpoint before PDF/export implementation

The form was sourced directly from suisa.ch (`WA Film 2011-01` main form + `WA Film II 2011-01` continuation). Form revisions are infrequent but possible, and previously nothing actually forced a re-check before the PDF layout was built against it — this section fixes that with a real, dated checkpoint rather than leaving it as a permanent "known gap" nobody revisits.

**Checkpoint: before implementation of `ROADMAP.md` D11/T11.2 (PDF export) begins**, re-verify the form is still `WA Film 2011-01`/`WA Film II 2011-01`:

1. Re-fetch the current form directly from suisa.ch's Film Department declaration-forms page and diff it against the version this spec's field mapping (§4) was built from.
2. If the published version differs, or reasonable doubt exists, email `filmproduction@suisa.ch` directly to confirm the current authoritative version before finalizing the PDF layout.
3. Record the outcome — date checked, version confirmed, any differences found — in `docs/DECISIONS.md`, the same way every other architectural decision in this project is tracked, not just informally noted somewhere.

This does not affect the architecture; only individual field/label wording would change if SUISA revises the form. `ROADMAP.md` D11 names this checkpoint as its own Task (T11.3) and gates T11.2 on it explicitly — it is a real gate, not an aspirational note.

## 3. Functional Scope (data-model relevant)

1. Import a WAV file (up to ~3 hours) as a `Project`'s `AudioAsset`.
2. Detect candidate `Cue`s via embedded WAV markers and/or silence-gap analysis.
3. Let the user edit/confirm Cues and attach right-holder (`Person`/`Label`) information and rights shares.
4. Maintain a production-level `Setup` (the SUISA form header).
5. Validate the data set against SUISA's rules (100%-share sums, required attachments for certain roles).
6. Export the finished cue sheet as PDF (visually matching the SUISA form layout) and XLSX (tabular, one row per Cue/right-holder, for internal use and easy re-editing).

UI flows and use-case logic are out of scope for this document — see `CLAUDE.md` for architectural rules governing where that logic lives.

## 4. Data Schema

Types: `String`, `String?` (optional String), `Int`, `Decimal`, `Bool`, `Date`, `UUID`, `enum`, `Set<T>`, `[T]` (ordered array). `MediaDuration` and `Timecode` are value types fully defined in this document (§4.8, §4.9) — this document is the sole authoritative source for them; see §5.

### 4.1 `Project`

| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | `UUID` | required | |
| `name` | `String` | required | internal working name; may differ from `setup.title` |
| `createdAt` | `Date` | required | |
| `updatedAt` | `Date` | required | |
| `audioAsset` | `AudioAsset?` | optional — absent until an audio file is imported | see §4.10 |
| `waveformPeaks` | `WaveformPeaks?` | optional — absent until generated (automatically, immediately after import) | see §4.15; deliberately a sibling field to `audioAsset`, not nested inside it — keeps `AudioAsset`'s "metadata-only, no sample data" invariant unambiguous |
| `setup` | `Setup` | required | 1:1 |
| `cues` | `[Cue]` | required (may be empty pre-analysis) | ordered; order is display order, not a stored field on `Cue` |
| `people` | `[Person]` | required (may be empty) | project-scoped right-holder directory |
| `labels` | `[Label]` | required (may be empty) | project-scoped right-holder directory |

### 4.2 `Setup`

One per `Project`. Mirrors the SUISA WA Film form header.

| Field | Type | Required | SUISA form field | Notes |
|---|---|---|---|---|
| `title` | `String` | **required** | "Title" | |
| `subtitle` | `String?` | optional | "(and sub-title, if any)" | |
| `producer` | `[Party]` | **required for export (≥1), empty array at the type level when unset** | "Producer (complete address)" | one or more, not at most one — reverses an earlier, explicitly-confirmed decision that this stay single-valued (`ROADMAP.md` D7, later round; see `docs/DECISIONS.md` for the reversal's full record). An empty array is this field's own honest "not yet chosen" value, the same pattern `productionTypes: Set<ProductionType>` already uses — not folded into the `PersonIntendedRole` roster mechanism, since a producer can be a `Label` (production company), which `PersonIntendedRole` (`Person`-only) can't represent. Export-required-ness is enforced by `ValidateCueSheetUseCase` (`ROADMAP.md` D11), not the type. |
| `directorOrPrincipal` | `[Party]` | **required for export (≥1), empty array at the type level when unset** | "Director / principal (commercials and Spots)" | form frames the label around commercials/spots but the field applies to all production types; same shape and reasoning as `producer`, above |
| `productionRuntime` | `MediaDuration` | **required** | "Playing time of film or production" | |
| `totalMusicRuntime` | `MediaDuration` | **required** | "Total music playing time" | source of truth and update rule fully defined in §4.14 |
| `productionYear` | `Int` | **required** | "Production year" | |
| `knownOrFutureBroadcasts` | `String?` | optional | "Already known or future broadcasts or screenings" | free text: countries, broadcasters, festivals, companies |
| `containsAdditionalUndeclaredWorks` | `enum { yes, no, notKnown }` | **required** | "Does the film...contain any other musical works..." | |
| `productionTypes` | `Set<ProductionType>` | **required, ≥1** | checkbox grid | see 4.2.1 |
| `otherProductionTypeDescription` | `String?` | required iff `productionTypes` contains `.other` | "other (please indicate)" | |
| `isanNumber` | `String?` | optional | "ISAN No" | "where known" on the form |
| `suisaRegistrationNumber` | `String?` | optional, not user-entered | "SUISA-No" | assigned by SUISA after submission; app should treat as read-only reference once known |
| `seriesTitle` | `String?` | optional | — | not on the form; needed for `.series` productions |
| `seasonNumber` | `Int?` | optional | — | not on the form |
| `episodeNumber` | `Int?` | optional | — | not on the form |
| `episodeTitle` | `String?` | optional | — | not on the form |
| `productionCountry` | `String?` | optional | — | not on the form; useful context for broadcasts + SWISSPERFORM reuse |
| `language` | `String?` | optional | — | not on the form |
| `timecodeFrameRate` | `TimecodeFrameRate` | **required, app-internal** | — | not on the form; the display frame rate used only to format `Cue.startTimecode`/`EmbeddedMarker.position` as `HH:MM:SS:FF` in the editor UI. Default `.fps25`. Never exported — SUISA durations are declared via `MediaDuration` (`HH:MM:SS`), not frame-accurate. See §4.9. |
| `timecodeStart` | `Timecode?` | optional, app-internal | — | not on the form; a production-level starting reference point for the editor UI's overall timecode display, formatted `HH:MM:SS:FF` via `timecodeFrameRate` the same way `Cue.startTimecode` is (§4.9). A genuinely new field found missing from this schema during `ROADMAP.md` D7's screen-reorder work — like `beitrag`/`exploitationTypes`/`broadcastDetails` below, it was in the original product brief but never actually mapped anywhere. Stays honestly optional at the type level; `CreateProjectUseCase` (not this type's own initializer default) gives a brand-new `Project` a real, deliberately-chosen starting value (`09:59:52:00`), the same "explicit at the call site" distinction already drawn for `declarationDate`/`productionTypes` in that Use Case. Never exported — SUISA declarations don't reference on-screen position, the same reasoning `Cue.startTimecode` is never exported. See `docs/DECISIONS.md`. |
| `declarant` | `Party?` | **required for export, optional at the type level** | "Particulars of the declaring person or publisher" | same optionality reasoning as `producer`, above |
| `declarationDate` | `Date` | **required** | "Date and signature" | defaults to export date |
| `attachmentTypes` | `Set<AttachmentType>` | optional | "Attachment(s)" | see 4.2.2; informational flags only — the app does not manage the physical attachments themselves |
| `otherAttachmentDescription` | `String?` | required iff `attachmentTypes` contains `.other` | "Other (please indicate)" | |
| `beitrag` | `String?` | optional — see note below | — | not on the physical WA Film form; a real field from the original product brief found missing from this schema during `ROADMAP.md` D7 planning (`docs/DECISIONS.md`) |
| `exploitationTypes` | `Set<ExploitationType>` | optional — see note below | — | "Verwertung"; see §4.2.3. Distinct from `productionTypes`: that's *what kind* of production this is, this is *how/where it's being distributed* (cinema, TV, festival, …) |
| `otherExploitationTypeDescription` | `String?` | required iff `exploitationTypes` contains `.other` | — | |
| `broadcastDetails` | `[BroadcastDetails]` | optional — see note below | — | "Sendedatum" ("Sender, Sendung, Datum der Sendung"); see §4.2.4. Deliberately separate from `knownOrFutureBroadcasts` (free text, general "broadcasts/screenings" notes) — this is structured broadcaster/programme/date data, one or more entries. **Originally scoped as a single optional instance (`BroadcastDetails?`)** when this field was added during D7 planning, explicitly not a repeatable list at the time; reversed to `[BroadcastDetails]` once the Setup screen was actually in use and a real need for multiple broadcasts (different broadcasters/dates for the same production) became apparent. See `docs/DECISIONS.md` for both the original scoping and this reversal. |

Not modeled as app-editable fields: "ISAN No" registration workflow beyond storing the string, and "Registration date/employee initials" (explicitly "to be completed by SUISA" on the form — SUISA-internal, never app-authored).

**`beitrag`/`exploitationTypes`/`broadcastDetails`'s export-required-ness is unresolved as of D7 planning — flagged explicitly, not silently decided.** These three fields render on both the PDF and XLSX export when present, and don't block export when absent, matching how `isanNumber`/`seriesTitle` already behave — but whether any of the three should actually be export-blocking-required, matching SUISA's real WA Film form requirements, isn't known with confidence (none of the three was in this document's original field-by-field mapping from the physical form). **Confirm against the real form at `ROADMAP.md` D11/T11.3's SUISA revalidation checkpoint** (§2.3) before `ValidateCueSheetUseCase` is implemented — the same checkpoint already gates T11.2's PDF layout work on re-verifying the form version, so this rides along with an already-planned step rather than needing a new one. See `docs/DECISIONS.md`.

#### 4.2.1 `ProductionType` (enum, from the form's checkbox grid)

`.featureFilm`, `.shortFilmCinema`, `.tvFeatureFilm`, `.tvShotFilm`, `.series`, `.documentaryFilm`, `.tvBroadcast`, `.leadInStationID`, `.educationalFilm`, `.commercial`, `.corporateFilm`, `.videoClip`, `.multimedia`, `.other`

Modeled as a `Set` (not a single value) because the form presents independent checkboxes, e.g. a production could legitimately be both `.series` and `.tvBroadcast`.

#### 4.2.2 `AttachmentType` (enum)

`.score`, `.agreement`, `.soundOrVideoCarrier`, `.other`

#### 4.2.3 `ExploitationType` (enum) — "Verwertung"

`.cinema`, `.tv`, `.festival`, `.other`

Modeled as a `Set` (not a single value), same reasoning as `ProductionType`/`AttachmentType`: a production can legitimately use more than one exploitation channel over its lifetime (e.g. cinema release followed by a later TV broadcast). Not on the physical WA Film form; found missing from this schema during `ROADMAP.md` D7 planning (`docs/DECISIONS.md`).

#### 4.2.4 `BroadcastDetails` (struct) — "Sendedatum"

| Field | Type | Notes |
|---|---|---|
| `broadcaster` | `String?` | "Sender" — the broadcaster's name |
| `programmeName` | `String?` | "Sendung" — the programme/show name |
| `date` | `Date?` | "Datum der Sendung" — the broadcast date |

All three sub-fields optional: none is on the physical form, and a value can be partially known (a confirmed broadcaster before an exact air date is set). No `id` field — no independent identity outside the one `Setup` that holds it, the same shape as `PostalAddress`/`Party` (`CLAUDE.md`, "Domain Model Value-Type Conformances"). Conformances: `Equatable`, `Sendable`. No `Codable`.

`Setup.broadcastDetails: [BroadcastDetails]` — one production can have more than one entry (different broadcasters/dates), reversing this field's originally single-instance scoping (§4.2, above) once the Setup screen was actually in use and a real need for multiple broadcasts became apparent. An empty array is this field's own honest "not yet entered" value, the same pattern `Setup.producer`/`.directorOrPrincipal` already establish — no double-optional trick needed. List identity for editing UI is by array position, same as those two fields. See `docs/DECISIONS.md`.

### 4.3 `Cue`

Many per `Project`, ordered. One SUISA "musical work" entry.

| Field | Type | Required | SUISA form field | Notes |
|---|---|---|---|---|
| `id` | `UUID` | required | — | |
| `title` | `String` | **required** | "Title of Nth work" | |
| `workNumber` | `String?` | optional | "Work No" | "where known" |
| `duration` | `MediaDuration` | **required** | "Playing time" / "Duration" | total duration this work is used in the production |
| `rightHolders` | `[CueRightHolder]` | **required, ≥1** | "Right-holder...with status" block | |
| `isArrangementOfProtectedOriginal` | `Bool` | **required** (defaults to `false`) | — | not itself printed on the form, but not a purely app-internal workflow aid either: this is the condition §4.4/§4.6 refer to as "the original work is still copyright-protected" — it's what `ValidateCueRightHolderSharesUseCase` checks to decide whether `CueRightHolder.arrangementAuthorizationAttached` is required for any `.arranger`-role right-holder on this work. A property of the work itself, not of any one right-holder row, since it doesn't depend on who the arranger is. Defaults to `false` (the common case — most works aren't arrangements of a still-protected original) rather than being left with no default, the same reasoning as `Setup.attachmentTypes` defaulting to an empty set: a real, safe default exists, unlike e.g. `Setup.productionTypes`, which has none |
| `source` | `enum { embeddedMarker, detectedFromAudio, manual }` | optional, app-internal | — | not exported to the SUISA document; drives editor UI provenance display. **Reclassification rule:** editing any field of a `Cue` via `UpdateCueUseCase`'s edit path sets `source = .manual`, regardless of the field changed or the cue's prior source — see §4.19 |
| `startTimecode` | `Timecode?` | optional, app-internal | — | not exported; SUISA wants usage duration, not on-screen position. See §4.9 for why this is a distinct type from `duration`. |
| `notes` | `String?` | optional, app-internal | — | not exported |

**TC In, TC Out, and Length — three related cue-sheet display values, one shared nil-safety rule.** New this pass, found during a pre-D9/D10 UI scope review (`docs/DECISIONS.md`, 2026-08-14) that checked what `ROADMAP.md` D10/T10.2's `CueTableView` actually displays for a cue's position and duration.

- **TC In** — `Cue.startTimecode` itself, formatted `HH:MM:SS:FF` via `Setup.timecodeFrameRate` (§4.9). Already a stored field; this just names it as a display value.
- **TC Out** — **derived, never stored:** `Timecode(offsetSeconds: startTimecode.offsetSeconds + duration.seconds)`, computed at the point a screen renders it (`ACFeatures`-layer, the same "compute at the point of rendering, don't persist a second copy" pattern already established for `WaveformDisplayData`/`CueSheetPageLayout`, though this is plain addition, not I/O — no new Repository method or Use Case). Formatted `HH:MM:SS:FF`, same as TC In, since it's a position, not a length. This is well-defined *whenever `startTimecode` is present* — confirmed during this review that `Cue.duration` cannot represent a work's cumulative usage across multiple non-contiguous placements (nothing in `EmbeddedMarker`, a single point per §4.10 not a range, or in `DetectCuesUseCase`'s one-cue-per-contiguous-region construction, supports that reading), so `start + duration` is always a single, well-defined end point for any cue that has a start at all.
- **Length** — `Cue.duration`, formatted **`MM:SS`** — a documented, deliberate exception to §4.8's general `HH:MM:SS` `MediaDuration` formatting rule, scoped specifically to this cue-sheet display context. `Setup.totalMusicRuntime`/`.productionRuntime` (§4.8) keep `HH:MM:SS`, since aggregate production-level runtimes can genuinely run past an hour; a single cue's usage duration realistically never does, and `MM:SS` reads better for that common case without losing information.

**The nil-safety rule, stated once here, applying to TC In and TC Out — not Length:** `Cue.startTimecode` is optional (`Timecode?`). A cue added via "+ Add Cue" (§4.19, `ROADMAP.md` D10/T10.2) is never tied to any position in the imported audio and is never assigned one automatically — it may permanently stay that way if the user never sets one. Whenever `startTimecode` is `nil`: **TC In displays a placeholder, `"—"`, and TC Out — being derived from `startTimecode`, undefined without it — displays the same placeholder**, never a bogus `0 + duration` computation. This is one rule, defined here once; anywhere TC In/TC Out are displayed references this rule rather than restating or independently reinventing it.

**Length has no analogous gap — checked directly, not assumed.** `Cue.duration` is `MediaDuration`, **not optional**: every `Cue`, including one freshly created via "+ Add Cue," has a real, concrete `duration` value — the type has no `nil` state to represent "no duration yet." A newly-added cue's `duration` defaults to `MediaDuration.zero` (`ROADMAP.md` T10.1's add path), and `00:00` is a legitimate, literal, always-safely-displayable value at that point, not a missing-data state — it means "zero length so far," the same way a fresh numeric field starting at `0` isn't "absent." Length therefore needs no placeholder and no nil-handling anywhere.

### 4.4 `CueRightHolder`

Sub-entity of `Cue`; one row per right-holder per work.

| Field | Type | Required | SUISA form field | Notes |
|---|---|---|---|---|
| `party` | `Party` | **required** | "Name, first name or publishing company" | resolved to display data via `PartyResolver`, §4.13 |
| `role` | `enum { composer, author, arranger, publisher, performer }` | **required** | legend: C / A / AR / E, plus app-only `.performer` | see note below — `.performer` reverses this document's original performer exclusion (§2.2) |
| `performanceBroadcastShare` | `Decimal` (%), scaled to 2 decimal places | **required** | "Performances Broadcasts (%)" | see §4.6 for the exact-equality sum validation this scale enables. **Meaningless for `.performer` rows** — excluded from the sum, see below |
| `mechanicalRightsShare` | `Decimal` (%), scaled to 2 decimal places | **required** | "Mechanical rights (%)" | see §4.6. Same `.performer` exclusion as above |
| `publishingContractAttached` | `Bool` | required iff `role == .publisher` | "(join copy of publishing contract)" | |
| `arrangementAuthorizationAttached` | `Bool` | required iff `role == .arranger` and `Cue.isArrangementOfProtectedOriginal == true` (§4.3) | form footnote on arrangements | |

**`.performer` ("Interpret*in") — added during `ROADMAP.md` D7 planning, reversing this document's original performer-exclusion decision (§2.2).** Informational only within AutoCue:

- **Not part of either 100%-share sum** (§4.6) — `ValidateCueRightHolderSharesUseCase` excludes `.performer` rows from both `performanceBroadcastShare`/`mechanicalRightsShare` totals. SUISA's WA Film form has no percentage-share column for performers; the C/A/AR/E legend and its two share columns are composer/author/arranger/publisher only. A `.performer` row's two share fields stay non-optional `Decimal` (defaulting to `0`) for structural consistency with the other four roles, rather than restructuring `CueRightHolder` to make them role-conditional — a larger, separate change this addition doesn't call for on its own.
- **Not rendered on the PDF export** (§4.16, `ROADMAP.md` D11/T11.2) — the physical form's right-holder block has no slot for a 5th role.
- **Rendered on the XLSX export** (tabular, unconstrained by the physical layout, §3) — extends §2.2's existing "reference data for SWISSPERFORM self-registration" framing rather than contradicting it; see §2.2.

See `docs/DECISIONS.md` for the full reasoning behind this reversal.

### 4.5 `Person` and `Label` (right-holder identity)

The SUISA form allows "Name, first name **or publishing company**" everywhere a right-holder or production contact is named. AutoCue models this as two identity types plus a reference enum, rather than duplicating fields across every place a party can appear.

**`Person`** (individual):

| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | `UUID` | required | |
| `firstName` | `String` | **required** | |
| `lastName` | `String` | **required** | |
| `ipiNumber` | `String?` | optional | not printed on this specific paper form, but standard CISAC identifier used across SUISA's digital systems; recommended for disambiguation, not enforced |
| `address` | `PostalAddress?` | optional generally; **required** when this `Person` is used as `Setup.producer`, `Setup.directorOrPrincipal`, or `Setup.declarant` | form mandates "complete address" for those roles only |
| `email` | `String?` | optional | app convenience, not on the form |
| `swissPerformNumber` | `String?` | optional | for individuals who also self-register AV participation with SWISSPERFORM (§2.2) |
| `intendedRoles` | `Set<PersonIntendedRole>` | optional (empty set = none), app-internal only | **never exported to the SUISA document; not a SUISA field at all.** A UI-organizing hint only — which of the Setup screen's collaborator-roster buckets (Komponist\*in/Arrangeur\*in/Interpret\*in) this `Person` has been added under (`ROADMAP.md` D7). A `Set`, not a single optional value, since a real person can hold more than one roster role on the same `Project` (e.g. both Komponist\*in and Interpret\*in) — an earlier revision of this field allowed at most one. Does **not** determine or default any `Cue`-level `CueRightHolder.role` assignment (§4.4) — that's a separate, explicit, per-Cue decision made later at D10. See `docs/DECISIONS.md`. |

`PersonIntendedRole` (enum): `.composer`, `.arranger`, `.performer` — deliberately a smaller, distinct set from `CueRightHolderRole` (§4.4), which also has `.author`/`.publisher` and is a real, exported, per-Cue-per-right-holder assignment. `PersonIntendedRole` is neither of those things — it's a directory-level memory aid, nothing more.

**`Label`** (corporate right-holder: publisher, production company, broadcaster):

| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | `UUID` | required | |
| `name` | `String` | **required** | |
| `address` | `PostalAddress` | **required** | form mandates "complete address" wherever a company stands in |
| `ipiNumber` | `String?` | optional | **not offered by the editor UI, for any `Label`, in any context — corrected from an earlier revision of this document, which described this as a "publisher CAE/IPI number."** Companies never carry an IPI number under any circumstance, confirmed directly during `ROADMAP.md` D7's later rounds — unlike `Person.ipiNumber`, which is real and shown, just conditionally hidden for the Producer*in/Regisseur*in creation flow specifically (§4.5, above). Still round-tripped unchanged on edit — an existing `Label` created before this correction that already has a value here isn't silently cleared, the same "hidden, not deleted" pattern `Person.swissPerformNumber` already establishes. See `docs/DECISIONS.md`. |
| `kind` | `enum { publisher, productionCompany, broadcaster, other }?` | optional, app-internal | not on the form; used only for UI grouping |
| `intendedForLabelRoster` | `Bool` | required, app-internal, defaults `false` | **never exported to the SUISA document; not a SUISA field at all.** A UI-organizing hint only — whether this `Label` has been added to the Setup screen's standalone "Label" roster bucket, the same concept `Person.intendedRoles` (§4.5, above) already establishes for `Person`, applied to `Label`'s one equivalent roster. A plain `Bool`, not a `Set<Enum>`, since `Label` has only one such roster (unlike `Person`'s three) — see `CLAUDE.md` rule 7. Set automatically when a brand-new `Label` is created from that bucket's own picker, or when an *existing* `Label` is explicitly selected there; never inferred from any other context (e.g. Producer*in's own "+ New Company"/selection never sets this). Added during `ROADMAP.md` D7's later rounds after a real, confirmed bug: without this field, the standalone Label bucket showed the *entire* project directory unfiltered, so a `Label` created via Producer*in silently appeared there too, despite never having been selected for that bucket. See `docs/DECISIONS.md`. |

**`Party`** (reference type, not persisted independently):

```
enum Party {
    case person(Person.ID)
    case label(Label.ID)
}
```

Used for: `Setup.producer`, `Setup.directorOrPrincipal`, `Setup.declarant`, `Settings.defaultDeclarant`, `CueRightHolder.party`. Deletion of a referenced `Person`/`Label` is guarded — see §4.12. Resolution to display data is centralized — see §4.13.

**`PostalAddress`** (shared value type): `street`, `postalCode`, `city`, `country` — all `String`, all required whenever a `PostalAddress` is present at all (i.e., "complete address" per the form means all four parts, not a bare name).

### 4.6 Cross-field validation rules (enforced in Domain Use Cases, not in the structs)

- Per `Cue`: `Σ rightHolders[].performanceBroadcastShare == 100%`.
- Per `Cue`: `Σ rightHolders[].mechanicalRightsShare == 100%`.

  **Rounding/tolerance policy for both sums above:** `performanceBroadcastShare` and `mechanicalRightsShare` are `Decimal` values scaled to exactly 2 decimal places (hundredths of a percent — matching the precision the printed SUISA form supports). The 100%-sum check is **exact equality against `100.00`, with zero tolerance band** — deliberately, not approximately. This is precise specifically *because* `Decimal` performs exact base-10 arithmetic: unlike `Double`, summing `Decimal` values at a fixed scale never accumulates binary floating-point rounding error, so no epsilon/tolerance comparison is needed to absorb arithmetic noise the way it would be with a `Double`-based sum — this is the actual reason `Decimal` was chosen for these two fields in the first place (§4.4). A legitimate uneven split — e.g. three right-holders at `33.33`, `33.33`, `33.34` — sums to exactly `100.00` under `Decimal` arithmetic and passes with no special-casing. A sum of `99.99` or `100.01` is treated as a genuine data-entry error, not a rounding artifact to be tolerated, and is flagged (blocking or warning per `Settings.shareValidationStrictness`, below). The domain model does not enforce the 2-decimal-place scale as a hard, compiler-checked constraint — `Decimal` has no such type-level restriction, and a custom validator for it is unneeded complexity this rule doesn't call for. Constraining user input to 2 decimal places is a Presentation-layer concern (input field formatting), out of scope for this document per §3.

- `Setup.declarant` must be non-`nil`, and `Setup.producer`/`.directorOrPrincipal` must each be non-empty (≥1 entry), before export (§4.2) — the export-required-field checks in this list driven by the type's own "unset" sentinel (`nil` or `[]`) rather than a business condition on otherwise-present data, since `Party` itself has no "none" case to check against.
- `Setup.productionTypes` must be non-empty.
- `Setup.otherProductionTypeDescription` required iff `.other ∈ productionTypes`.
- `Setup.otherAttachmentDescription` required iff `.other ∈ attachmentTypes`.
- `CueRightHolder.publishingContractAttached` must be `true` before export iff `role == .publisher`.
- `CueRightHolder.arrangementAuthorizationAttached` must be `true` before export iff `role == .arranger` and `Cue.isArrangementOfProtectedOriginal == true` (§4.3).
- Whether a failed rule **blocks** export or only **warns** is controlled by `Settings.shareValidationStrictness`.

`Setup.totalMusicRuntime`'s auto-recompute (§4.14) and `Person`/`Label` deletion guarding (§4.12) are separate, non-optional domain rules — not part of this list because they aren't pass/fail validations checked before export; they're invariants enforced continuously as data changes.

### 4.7 `Settings`

App-level only; not part of the SUISA document.

| Field | Type | Notes |
|---|---|---|
| `defaultDeclarant` | `Party?` | pre-fills `Setup.declarant` on new projects; also scanned by the delete guard, §4.12 |
| `defaultProductionCountry` | `String?` | |
| `exportLanguage` | `enum { de, fr, it, en }` | SUISA's form exists in all four Swiss/working languages |
| `autoComputeTotalMusicRuntime` | `Bool` (default `true`) | see §4.14 for the full update rule and owning Use Case |
| `shareValidationStrictness` | `enum { warnOnly, blockExport }` | |
| `defaultExportFormat` | `ExportFormat` | see below |
| `audioAnalysisDefaults` | `AnalysisSettings` | app-wide defaults applied to new imports; see §4.11 |

**`ExportFormat`** (enum): `.pdf`, `.xlsx`, `.both` — named here explicitly, not left as an inline anonymous enum, because it's also the parameter type `ExportCueSheetUseCase`/`ExportRepository` take to select what a given export run produces (`CLAUDE.md` rule 2, "Long-Running Operations" table) — the same type used for `Settings.defaultExportFormat` and for one specific export invocation, not two independent concepts that happen to share a shape. Adding a new export format (`CLAUDE.md` rule 2) means adding a case here.

### 4.8 `MediaDuration` (renamed from `Duration`)

Renamed from the originally-planned `Duration` to avoid colliding with the Swift standard library's own `Duration` type (`Swift.Duration`), which ships as part of Swift Concurrency (`ContinuousClock`, `Task.sleep(for:)`, etc.) and is implicitly in scope in virtually every file that touches `async`/`await` timing. Reusing that name for an unrelated domain type would produce constant, confusing ambiguity errors the moment both are in scope — a landmine far cheaper to defuse now, before any code exists, than after `ROADMAP.md` D1/T1.4 ships it.

`MediaDuration` was chosen over the alternative `CueDuration` because the type isn't cue-specific: it's also used for `Setup.productionRuntime` and `Setup.totalMusicRuntime` — any length of media time, not just one cue's.

Represents a **length** of time — "how long," never "where." Contrast with `Timecode` (§4.9), which represents a position.

| Field | Type | Notes |
|---|---|---|
| `seconds` | `Double` | total length, in seconds. Deliberately `Double`, not `Decimal` — durations are formatted, compared, and summed for display/scheduling purposes, not accounted to an exact fixed target the way `CueRightHolder` percentage shares are (§4.4 uses `Decimal` specifically because the 100%-sum validation needs exact decimal arithmetic; `MediaDuration` has no equivalent exactness requirement). |

Conformances: `Equatable`, `Comparable`, `Hashable`, `AdditiveArithmetic` (`+`, `-`, `.zero`) — `AdditiveArithmetic` is required directly by §4.14's `Σ cues[].duration` computation. No `Codable` — see `CLAUDE.md`, "Domain Model Value-Type Conformances," for why blanket `Codable` was removed project-wide.

Formatting: `HH:MM:SS`, no frames. Cue durations and runtimes are declared to SUISA as a rights-accounting total, not located frame-accurately within the production — frame precision belongs to `Timecode`, not here.

### 4.9 `Timecode` and `TimecodeFrameRate`

Represents an absolute **position** within an `AudioAsset` — an offset from the start of the file. Contrast with `MediaDuration` (§4.8), a length. Used only by `Cue.startTimecode` and `EmbeddedMarker.position` (§4.10) — both app-internal, never exported to the SUISA document (§4.3 already notes `startTimecode` isn't exported; SUISA wants total usage duration, not on-screen position).

| Field | Type | Notes |
|---|---|---|
| `offsetSeconds` | `Double` | precise offset from the start of the audio file, in seconds; sample-accurate at the point it's captured (derived from a sample index ÷ sample rate during import/analysis — the stored value is a time offset, not a raw sample count) |

**Where the frame rate comes from — this is not audio metadata.** A WAV file carries no video frame rate; nothing in the RIFF/BWF format declares one. AutoCue is not synced to picture, only to itself, so "frame" here is a **display convention borrowed from film/TV editing practice**, not a property of the source audio or a synced video frame boundary. The frame rate used to format a `Timecode` as `HH:MM:SS:FF` comes from `Setup.timecodeFrameRate: TimecodeFrameRate` (§4.2) — a per-production, user-configurable, app-internal field, because different productions AutoCue is used on may be mastered at different frame rates, and a user reading cue positions wants them to match their own edit timeline. `Timecode.offsetSeconds` itself never changes when `timecodeFrameRate` changes — only its *formatted display* does, computed on demand. This also means changing `Setup.timecodeFrameRate` after cues already exist is always safe and needs no migration: it's a pure reformat of already-correct underlying data.

`TimecodeFrameRate` (enum):

| Case | Nominal FPS (`FF` field modulus) | Real FPS (used for frame-count math) | Drop-frame? |
|---|---|---|---|
| `.fps24` | 24 | 24.0 | no — no real/nominal mismatch to correct for |
| `.fps25` | 25 | 25.0 | no |
| `.fps29_97NonDrop` | 30 | 29.97 | no |
| `.fps29_97Drop` | 30 | 29.97 | **yes** |
| `.fps30` | 30 | 30.0 | no |

Default: `.fps25` (PAL/European broadcast convention, matching AutoCue's Swiss/SUISA target market) — arbitrary but documented, freely overridable per `Setup`. Choosing `.fps25` as the default is unaffected by drop-frame support existing as an option: nothing selects `.fps29_97Drop` unless the user explicitly does, for material that's actually NTSC-derived.

Drop-frame support was added in v1 rather than deferred — see `docs/DECISIONS.md` for why (short version: `Timecode`/`TimecodeFrameRate` are foundational types many later milestones depend on directly; retrofitting a second timecode mode after that dependency exists is far more expensive than getting the enum shape and conversion algorithm right once, up front, and NTSC-derived source material is a real case for this app, not a hypothetical one).

**Why only `.fps29_97` needs a drop-frame variant.** Drop-frame numbering exists specifically to reconcile a *real* frame rate that doesn't evenly divide a second (29.97, in this app's case) with a *nominal* display rate that does (30). `.fps24`/`.fps25`/`.fps30` have no such mismatch — real and nominal are identical — so a drop-frame variant of any of them would be meaningless. This is why the enum only splits `.fps29_97` into `NonDrop`/`Drop`, not every case.

**`Timecode` itself stays frame-rate-agnostic.** It stores nothing but `offsetSeconds: Double` — a pure position, with no frame rate and no drop/non-drop mode attached to it. Whether a given offset gets formatted as drop-frame or non-drop is entirely a property of the `TimecodeFrameRate` passed in at format time, never of the `Timecode` value itself. This is deliberate: it's what makes changing `Setup.timecodeFrameRate` later a pure reformat with no data migration (see above), and it's why drop-frame logic must never leak into `MediaDuration` (§4.8) — a length of time has no "position within a minute" to apply a skip-rule to in the first place.

**Frame calculation, non-drop-frame:**

```
totalFrames = round(offsetSeconds × realFPS)
hours   = totalFrames / (nominalFPS × 3600)
minutes = (totalFrames / (nominalFPS × 60)) mod 60
seconds = (totalFrames / nominalFPS) mod 60
frames  = totalFrames mod nominalFPS
```

**Frame calculation, drop-frame (`.fps29_97Drop`) — SMPTE drop-frame numbering.** The real (uncorrected) frame count is first converted into a *display* frame number, by re-inserting the frame-numbers that drop-frame timecode skips, before the same decomposition above is applied to it. The skip rule: **frame numbers 0 and 1 are skipped at the start of every minute, except every 10th minute** (minutes 0, 10, 20, 30, 40, 50). This corrects for 29.97fps running ~0.1% slower than nominal 30fps, so that drop-frame timecode stays aligned with wall-clock time at hour boundaries — e.g. exactly 3600 seconds of real elapsed time reads `01:00:00:00`, not something drifted by several seconds, which is the entire reason drop-frame exists.

```
dropped = 2                                    // frames skipped per non-exempt minute, at nominal 30fps
framesPerMinuteDropAdjusted = 1800 - dropped    // 1798
framesPer10Min = 18000 - dropped × 9            // 17982 (9 non-exempt minutes per 10-minute block)

d = realFrameCount / framesPer10Min             // integer division
m = realFrameCount mod framesPer10Min

if m < dropped:
    displayFrameNumber = realFrameCount + dropped × 9 × d
else:
    displayFrameNumber = realFrameCount + dropped × 9 × d + dropped × ((m − dropped) / framesPerMinuteDropAdjusted)

# then decompose displayFrameNumber exactly as in the non-drop formula above, using nominalFPS = 30
```

The inverse (parsing `HH:MM:SS:FF` back to an offset) reverses this: compute the naive nominal-30fps frame number from the fields, then subtract `dropped × (nonExemptMinutesElapsed)` to recover the real frame count, where `nonExemptMinutesElapsed = totalMinutes − totalMinutes/10`.

**Invalid drop-frame timecodes are rejected, not silently miscomputed.** Under drop-frame numbering, `FF` values 0 and 1 at `SS == 0` of a non-exempt minute don't correspond to any real frame — e.g. `00:01:00:00` and `00:01:00:01` don't exist; the first real frame of minute 1 is `00:01:00:02`. Parsing such a value must fail (return `nil`/throw), not produce a `Timecode` that silently reformats to a different string than what was entered.

Formatted as `HH:MM:SS:FF`, each component zero-padded to 2 digits. Drop-frame timecode conventionally uses a `;` separator immediately before the frame field (`HH:MM:SS;FF`) to visually distinguish it from non-drop timecode — applied here too.

**Verification:** this arithmetic is implemented and unit-tested in `Packages/ACCore/Sources/ACCore/Models/{Timecode,TimecodeFrameRate}.swift` / `Packages/ACCore/Tests/ACCoreTests/TimecodeTests.swift`, including the every-10th-minute exception specifically (the classic bug in drop-frame implementations) and a round-trip sweep across a 3-hour-equivalent frame range.

### 4.10 `AudioAsset`, `EmbeddedMarker`, `BroadcastWaveMetadata`

One `AudioAsset` per `Project`, present once audio has been imported (`Project.audioAsset` is optional — absent before that, §4.1). An immutable, derived snapshot produced by `AudioAnalysisRepository` from the source WAV file; the file on disk remains the source of truth for raw audio (`CLAUDE.md`, Single Source of Truth).

**`AudioAsset.embeddedMarkers` is never edited, including to "correct" a misjudged detection.** `EmbeddedMarker` is a factual record of what's literally embedded in the source WAV file's `cue`/`labl`/`ltxt` chunks — analogous to a photo's EXIF data — and editing it would misrepresent the source file's actual content, not just tweak an app opinion. What the user actually corrects when a detection is wrong is the app's *interpretation* of that data, which is what `Cue` (§4.3) represents, not `AudioAsset` itself. See §4.19 for the full architectural resolution of manual cue correction — it never touches this type, which is what keeps the immutability invariant below intact rather than quietly bent for editing purposes.

**Invariant: `AudioAsset` never contains raw or downsampled sample data (no PCM buffer, no waveform peak array).** It is bounded, metadata-only, and safe to hold fully in memory regardless of source file size — this is what keeps it a plain `ACCore` domain value type despite the "never load a full WAV into memory" constraint applying project-wide. The waveform-display data model this invariant explicitly excludes from `AudioAsset` is `WaveformPeaks` — a separate, explicitly-bounded sibling type on `Project`, not a field here — see §4.15.

| Field | Type | Notes |
|---|---|---|
| `id` | `UUID` | |
| `originalFileName` | `String` | display only; not a file-system path |
| `securityScopedBookmark` | `Data` | opaque sandboxed-file-access bookmark (`URL.bookmarkData`); `Data` is a Foundation type, so this stays valid in `ACCore` without an extra framework import |
| `duration` | `MediaDuration` | total length of the file |
| `sampleRate` | `Double` | Hz |
| `channelCount` | `Int` | |
| `bitDepth` | `Int` | |
| `embeddedMarkers` | `[EmbeddedMarker]` | from `cue`/`labl`/`ltxt` chunks; may be empty |
| `broadcastWaveMetadata` | `BroadcastWaveMetadata?` | from the `bext` chunk; `nil` if the file isn't BWF-tagged |
| `importedAt` | `Date` | |

**`EmbeddedMarker`** — one embedded cue-point marker:

| Field | Type | Notes |
|---|---|---|
| `id` | `UUID` | |
| `position` | `Timecode` | offset from the start of the file, §4.9 |
| `label` | `String?` | from the `labl` chunk, if present |
| `note` | `String?` | from the `ltxt` chunk's text, if present |

**`BroadcastWaveMetadata`** — from the `bext` chunk, when present:

| Field | Type | Notes |
|---|---|---|
| `description` | `String?` | |
| `originator` | `String?` | recording device/software |
| `originatorReference` | `String?` | |
| `originationDate` | `Date?` | |
| `timeReferenceSamples` | `UInt64?` | sample count since midnight, for external sync reference |

### 4.11 `AnalysisSettings`

App-level audio-analysis defaults, nested under `Settings.audioAnalysisDefaults` (§4.7) rather than flat fields on `Settings` — kept as its own type so it can be passed directly as a parameter to `DetectCuesUseCase`/`AudioAnalysisRepository` without those APIs depending on the whole `Settings` type. This section is the implementation *contract* for `ACAudioKit`'s silence/level detection (`ROADMAP.md` D8) — concrete enough that those Tasks have an unambiguous target, without prescribing the actual DSP code (window-size tuning, exact statistic used for noise-floor estimation, etc. remain implementation detail within this contract).

**Detection approach: windowed RMS level, not instantaneous/peak sample values — refined by a second, SuperFlux-based stage for cue *starts* only.** Audio is analyzed in fixed-length windows (`analysisWindowMilliseconds`), computed every `analysisWindowHopMilliseconds` — overlapping whenever the hop is smaller than the window length, which it is by default; see "RMS time resolution and threshold-crossing interpolation," below, for why window length and hop are two separate parameters — computing each window's RMS level in dBFS via `Accelerate`/vDSP (per `CLAUDE.md`'s "no hand-rolled sample loops" rule). A window is classified silent if its RMS level is below the effective threshold (see calibration, below). Peak/instantaneous-sample thresholding is deliberately not used — a single loud transient sample (a click, a digital pop) would otherwise misclassify an entire otherwise-silent window, and RMS-over-a-window is the standard, more stable technique for gap/silence-gate detection. RMS-threshold detection is stage 1 of a two-stage pipeline: it locates the *candidate region* for each boundary. Stage 2, **SuperFlux-based onset refinement**, then pinpoints the precise moment within that region — see "SuperFlux-based onset refinement," below, for why RMS alone isn't sufficient for every real case and how the two stages combine; "Why offset detection does not use SuperFlux or any onset-detection technique," below, for why this stage is never applied to cue *ends*; and "RMS time resolution and threshold-crossing interpolation," below, for what makes the RMS mechanism itself precise enough to meet the 1-frame target for cue ends without a SuperFlux-equivalent second stage.

| Field | Type | Default | Notes |
|---|---|---|---|
| `noiseFloorCalibrationMode` | `enum { manual, automatic }` | `.manual` | see "Threshold: manual vs. automatic," below |
| `silenceThresholdDb` | `Double` | `-40.0` | dBFS (≤ 0). Manual mode: used directly, unchanged for the whole file. Automatic mode: the fallback value if calibration is inconclusive; not the effective threshold otherwise — see below |
| `calibrationMarginDb` | `Double` | `6.0` | automatic mode only: headroom added above the *measured* noise floor to set the effective threshold |
| `noiseFloorReestimationIntervalSeconds` | `Double` | `300.0` | automatic mode only: how often the noise floor is re-measured across a file's duration — see "Time-varying noise floor," below |
| `analysisWindowMilliseconds` | `Double` | `50.0` | length of each RMS measurement window described above — governs estimate *stability* (a longer window averages out more noise/transients), not the time resolution at which boundaries are located; see `analysisWindowHopMilliseconds`, next |
| `analysisWindowHopMilliseconds` | `Double` | `10.0` | new this pass: how often a new RMS window is computed, independent of `analysisWindowMilliseconds`'s window *length* — windows overlap whenever this is smaller than the window length, as it is by default (`10.0`ms hop against a `50.0`ms window). Governs the time resolution at which threshold crossings can be located; must be ≤ `analysisWindowMilliseconds`, since a larger hop would leave gaps of audio no window covers. See "RMS time resolution and threshold-crossing interpolation," below |
| `minimumSilenceDurationSeconds` | `Double` | `2.0` | renamed from `minimumCueGapSeconds` for clarity — it measures a duration of silence, not an abstract "gap." Minimum duration a run of below-threshold windows must sustain, continuously, before it's treated as a boundary between two cues |
| `minimumCueDurationSeconds` | `Double` | `3.0` | a candidate non-silent region shorter than this is discarded (merged into whichever neighboring silence run absorbs it) rather than promoted to a `Cue` — guards against a short noise blip or brief room-tone swell being detected as a spurious musical work |
| `tailToleranceDb` | `Double` | `6.0` | see "Reverb tails," below |
| `tailCapSeconds` | `Double` | `2.0` | see "Reverb tails," below |
| `embeddedMarkerMergeToleranceSeconds` | `Double` | `1.0` | see "Combining with embedded markers," below |
| `superFluxRefinementSearchWindowSeconds` | `Double` | `0.5` | stage 2 only: how far, in seconds, before/after the stage-1 (RMS-threshold) candidate boundary the SuperFlux onset search looks — see "SuperFlux-based onset refinement," below. Bounds how far refinement can relocate a boundary from its stage-1 candidate; not a general search radius. Renamed from `spectralFluxRefinementSearchWindowSeconds` (2026-08-13) when stage 2 was upgraded from plain spectral flux to SuperFlux specifically; meaning unchanged |
| `superFluxHopSeconds` | `Double` | `0.01` | stage 2 only, new this pass: how often a new STFT frame — and therefore a new novelty-function value — is computed, i.e. the time resolution at which the refined boundary is ultimately reported. `0.01`s (`10`ms) matches Böck & Widmer's own reference configuration (44.1kHz sample rate, hop size `441` samples = `10`ms, ~100 frames/second). Pinned here explicitly, not left as an implementation-time-only value, for the same reason `analysisWindowHopMilliseconds` was pinned for the RMS mechanism (2026-08-13) rather than left open: unlike the filterbank resolution (~24 bands/octave, step 1 below — spectral fidelity only, doesn't affect the reported time grid), this value directly determines stage 2's reported-boundary quantization. See "SuperFlux hop size and reported-boundary resolution," below |
| `superFluxMaxFilterBandwidthBins` | `Int` | `3` | stage 2 only: width, in log-frequency filterbank bins, of the maximum filter applied across neighboring frequency bins to the log-magnitude spectrogram before computing the frame-to-frame novelty difference — the mechanism that suppresses vibrato/tremolo-driven false onsets. See "SuperFlux-based onset refinement," below. Must be odd (centered on the bin being filtered — `(n−1)/2` bins on each side); default `3` (one neighboring bin each side) matches Böck & Widmer's reference design |
| `superFluxAdaptiveThresholdWindowSeconds` | `Double` | `0.1` | stage 2 only, new this pass: length, in seconds, of the local window centered on a candidate frame over which the novelty function's local median is computed for adaptive peak-picking — see "Adaptive local peak-picking," below. Converted to a frame count at runtime directly from `superFluxHopSeconds`, above (`round(superFluxAdaptiveThresholdWindowSeconds / superFluxHopSeconds)` frames each side of center) — no longer an implementation-time-only conversion, now that the hop itself is pinned. Retires `superFluxOnsetSensitivity` — see "Adaptive local peak-picking," below, for why a single global sensitivity value is replaced outright rather than kept alongside these three fields |
| `superFluxAdaptiveThresholdMultiplier` | `Double` | `1.5` | stage 2 only, new this pass: dimensionless multiplicative margin (`λ`) applied to the local median novelty value computed over `superFluxAdaptiveThresholdWindowSeconds`, above — the primary adaptive-sensitivity control. See "Adaptive local peak-picking," below |
| `superFluxAdaptiveThresholdOffset` | `Double` | `0.05` | stage 2 only, new this pass: additive floor (`δ`), expressed as a fraction (`0`...`1`) of the peak novelty value within the current stage-2 search window (`superFluxRefinementSearchWindowSeconds`, above) — deliberately *not* an absolute novelty-function unit, since that scale is signal-level-dependent (see step 2, "Logarithmic magnitude compression," below); expressing it as a fraction of the window's own peak keeps the offset meaningful regardless of a given clip's absolute loudness. Guards the near-silent-window edge case (local median at or near zero) rather than acting as the primary discriminator — `superFluxAdaptiveThresholdMultiplier` carries that role. See "Adaptive local peak-picking," below |

Conformances: `Equatable`, `Hashable`, `Sendable` (consistent with every other `ACCore` value type — see `CLAUDE.md`, "Domain Model Value-Type Conformances"). No `Codable`.

**Threshold: manual vs. automatic.** Both are supported, switched via `noiseFloorCalibrationMode` — not an either/or product decision, because a single fixed dBFS threshold across arbitrarily different source recordings (a quiet studio mix vs. a location recording with real room noise) is fragile. In `.manual` mode, `silenceThresholdDb` is used exactly as configured. In `.automatic` mode, the noise floor is measured from the file itself (a leading sample window at import time), and the effective threshold is `measuredNoiseFloorDb + calibrationMarginDb` — the margin exists so ordinary ambient hiss just above the true noise floor isn't misclassified as "non-silent." If calibration can't produce a reliable measurement (e.g. a file with no quiet passage at all to sample), the fallback is `silenceThresholdDb` unchanged. The exact statistic used to estimate "the noise floor" from a sample window (e.g. a low percentile of window RMS values) is left to `ROADMAP.md` D8/T8.3 — the contract fixed here is *that* calibration happens this way and produces one effective-threshold-in-dBFS value per re-estimation window, not the literal statistic.

**Time-varying noise floor.** A single floor measurement for an entire 3-hour file doesn't hold up if the recording's ambient conditions genuinely change partway through (a real possibility for this app's actual use case — production audio spanning scene/location changes). Rather than one global calibration, `.automatic` mode re-estimates the noise floor on a rolling basis, once per `noiseFloorReestimationIntervalSeconds` (default every 5 minutes), each time using the same leading-sample-window technique applied to that interval. This is a deliberately simple periodic re-estimation, not a continuously-adaptive filter — a real, bounded mechanism for the common case (noise floor shifts a few times across a long file) without building a full adaptive noise-gate model that isn't needed yet.

**Ambience/room tone vs. silence.** The system does not attempt to semantically distinguish "quiet music" from "room tone" — both present identically to a level-based detector as continuous energy above the noise floor, and telling them apart is a *content-identity* question ("is this actually a musical work?"), not a signal-detection one. This is deliberately left to human review, not solved at the DSP layer: every detected boundary produces a `Cue` with `source == .detectedFromAudio` (SPEC.md §4.3), always user-confirmable/editable/deletable before export, never auto-finalized. The one signal-side mitigation is `minimumCueDurationSeconds`: a short blip of room tone bounded by two genuine silence gaps, too brief to plausibly be a musical work, is discarded rather than promoted to a spurious candidate `Cue`.

**RMS time resolution: hop size and threshold-crossing interpolation — closing the gap between the 50ms window and the 1-frame target.** "Boundary accuracy target," below, requires locating a boundary within 1 frame of the project's configured `Setup.timecodeFrameRate` — between roughly `33.3`ms (`.fps30`/`.fps29_97NonDrop`/`.fps29_97Drop`) and `41.7`ms (`.fps24`) depending on frame rate. Taken at face value, `analysisWindowMilliseconds`'s `50.0`ms default is coarser than this target. For cue *starts* this doesn't matter in practice — SuperFlux's stage 2 (below) relocates the boundary directly from the spectrogram, at `superFluxHopSeconds`'s own `10`ms time resolution (see "SuperFlux hop size and reported-boundary resolution," below) — finer than the RMS window's `50.0`ms — so stage 1's own precision is masked by stage 2 regardless. **For cue *ends* it matters completely**, because offsets have no equivalent second stage (see "Why offset detection does not use SuperFlux or any onset-detection technique," below) and are finalized entirely by this RMS mechanism — so the RMS mechanism's own resolution *is* the offset-accuracy budget, with nothing downstream to correct for it. Two additions, both plain RMS/energy-domain techniques — consistent with offsets deliberately staying off any onset-detection-family (spectral/novelty) technique — close this gap:

1. **Hop size, decoupled from window length.** `analysisWindowHopMilliseconds` (default `10.0`) sets how often a new RMS window is computed, independent of `analysisWindowMilliseconds` (the window's *length*, unchanged at its `50.0`ms default). Windows overlap whenever the hop is smaller than the window length, which it is by default — `50.0`ms windows, computed every `10.0`ms, so consecutive windows overlap by `40.0`ms of audio. This is the same frame-length/hop-length decoupling used by any STFT-based technique (SuperFlux's own spectrogram included, above): the window stays long enough to give a stable RMS estimate (this section's original reason for using RMS over instantaneous samples at all), while the hop determines how finely boundaries can be located in time, independent of that stability requirement. At the `10.0`ms default, hop-quantization alone already bounds any threshold-crossing error to at most `10.0`ms — comfortably inside even the tightest 1-frame tolerance (`33.3`ms) with better than 3× margin, before interpolation is even applied.
2. **Threshold-crossing interpolation, not window-quantized reporting.** A crossing is not reported as "the hop-window where the level first crossed" — which would still carry up to one hop's worth of quantization error on its own. Instead, the two RMS measurements straddling the effective threshold (the last window still on one side, the first window on the other) are linearly interpolated *in the dB domain* to locate the crossing instant between their window-center timestamps: `t_cross = t₁ + (thresholdDb − db₁) / (db₂ − db₁) × hop`. Interpolating in dB, rather than in linear amplitude, is deliberate: an exponentially-decaying amplitude envelope — the physically realistic shape of a reverb/release tail — is linear in dB by construction over any span short relative to the decay's own time constant, which one `10.0`ms hop comfortably is for any audible tail. This interpolation applies uniformly to every RMS threshold crossing this contract defines — the main `silenceThresholdDb` gap boundary and the stricter `silenceThresholdDb − tailToleranceDb` reverb-tail-truncation crossing ("Reverb tails," below) both use it, not just one of them.

Together, hop reduction alone already clears the tightest 1-frame tolerance with margin; interpolation removes the residual, hop-bounded quantization error rather than leaving it as a worst-case bound, and keeps the mechanism robust even if a project is ever configured with a coarser custom hop. This is a real, previously-unresolved gap this pass closes, not a restatement of an already-solved problem: before this addition, the RMS mechanism as originally specified — a 50ms window with no documented hop or interpolation — could not have reliably met the 1-frame target for cue ends, which have no downstream stage to correct for it the way SuperFlux corrects for it on cue starts.

**Performance note.** A `10.0`ms hop against a `50.0`ms window means roughly 5× more RMS windows computed than a naive non-overlapping (`hop == window`) implementation over the same file — on the order of ~1 million windows for a 3-hour file, each a small, `Accelerate`/vDSP-computed RMS over a bounded sample range read through the existing streaming reader (`ACAudioKit/Streaming`, per `CLAUDE.md`'s "never load a full file into memory" rule). This is well within the bounded-chunk, vDSP-vectorized architecture `CLAUDE.md`'s Performance Considerations already require, and doesn't change the kind of performance-budget test T8.3 already documents, only the specific budget number confirmed at implementation time. The same finer hop also incidentally sharpens the sustained-duration checks (`minimumSilenceDurationSeconds`, `minimumCueDurationSeconds`) — not the motivating reason for this change, but a consistent side benefit rather than a regression.

**SuperFlux-based onset refinement (stage 2, cue-*start* boundaries only — precise timing, not a semantic classifier).** RMS-threshold detection has a specific, known weakness: for a cue that fades in gradually or is mixed in deliberately quiet, there is no single clean moment where the level crosses any threshold, since the level ramps up by construction — wherever the threshold sits, the crossing point is somewhat arbitrary relative to where a human editor would actually place the cue's start, and tends to land later than the true onset.

Plain spectral flux (frame-to-frame change in FFT magnitude spectrum) is the standard MIR fix for this, but it has a specific failure mode that matters directly for this app's real material: film-score audio leans heavily on sustained strings, legato brass/woodwind swells, and vocal lines, and natural vibrato/tremolo in exactly this material produces small frame-to-frame spectral fluctuations that plain spectral flux reads as a sequence of spurious onsets — the note never actually re-attacked, but its energy wobbled slightly in frequency and amplitude, and a naive frame-to-frame difference can't tell the two apart. Stage 2 therefore uses **SuperFlux** specifically (Böck & Widmer, "Maximum Filter Vibrato Suppression for Onset Detection," DAFx 2013), an enhancement of plain spectral flux that adds an explicit vibrato/tremolo-suppression step — a maximum filter across neighboring frequency bins — before computing the frame-to-frame difference. The paper's published result is up to a 60% reduction in false-positive onsets on solo string and sung-vocal material specifically, without missing genuine onsets — precisely the instrumentation this app's real-fixture library and real-world usage are dominated by. SuperFlux is used here in preference to plain spectral flux as a specific, targeted fix for a failure mode this app's actual material triggers, not as an interchangeable "spectral flux, tuned differently."

**Signal chain, step by step, computed only within the stage-1 candidate region** (bounded by `superFluxRefinementSearchWindowSeconds` on either side of the stage-1 boundary — SuperFlux is never run over a whole file, only this bounded window, keeping stage 2's cost proportional to the number of candidate boundaries, not file length):

1. **Windowed STFT, then log-frequency-scaled magnitude spectrogram.** The candidate region is framed and transformed via STFT using a **Hann window**, computed every `superFluxHopSeconds` (default `0.01`s, `10`ms) — matching Böck & Widmer's own reference SuperFlux implementation, and standard practice for general-purpose spectral analysis of this kind. The window choice is a deliberate, stated choice, not an unspecified default: SuperFlux's novelty function operates on coarse, ~24-bands-per-octave log-frequency energy (step below), not on resolving closely-spaced sinusoidal partials at fine frequency resolution — the concern a different window family (e.g. a narrower-main-lobe/lower-sidelobe choice tuned for partial-tracking) would actually matter for. The resulting magnitude spectrogram is then mapped onto a logarithmic frequency scale via a triangular filterbank, at the paper's reference resolution of **~24 filter bands per octave**. This is documented here as the reference design point, per this section's convention for values that are precise-in-the-literature but implementation-confirmed at build time (the same treatment already given to the noise-floor-estimation statistic, above): the actual resolution used is confirmed at `ROADMAP.md` T8.3 implementation time, and this section is updated with what was chosen and why if it ends up differing from 24 bands/octave. Logarithmic (rather than the STFT's native linear-Hz) frequency spacing is what makes step 3's max filter operate over musically meaningful, roughly semitone-scale neighborhoods instead of arbitrary linear-Hz ones — vibrato/tremolo wobble is a roughly constant *musical* interval regardless of the note's absolute pitch, so a fixed bin-count neighborhood only suppresses it correctly on a log-frequency scale.
2. **Logarithmic magnitude compression.** Each filterbank output is compressed as `Y = ln(1 + γ·|X|)` (paper reference: `γ = 1`), the standard spectral-flux-family step that stops a handful of very loud bins from dominating the frame-to-frame difference computed in step 4 — a quiet secondary onset next to a loud sustained note would otherwise be invisible in the novelty function without this compression.
3. **Maximum filter across neighboring frequency bins — the vibrato/tremolo-suppression step.** For each frame, each bin's compressed magnitude is replaced with the maximum value found within a `superFluxMaxFilterBandwidthBins`-wide neighborhood of bins centered on it (default `3`: one neighboring bin on each side). Vibrato/tremolo shifts a note's energy slightly up/down in frequency and amplitude from one frame to the next without a new musical event occurring; taking the max across a small bin neighborhood means that small shift no longer registers as an *increase* relative to the previous frame's max-filtered value, because the previous frame's max-filtered value already "saw" the nearby energy the wobble shifted into. This is the entire mechanism that makes SuperFlux different from plain spectral flux — every other step in this chain is standard spectral-flux machinery.
4. **Half-wave-rectified frame-to-frame difference — the novelty function.** The novelty value at frame `n` is `Σ_k HWR(Y(n,k) − Ymax(n−1,k))`, where `Y(n,k)` is the (non-max-filtered) compressed magnitude at frame `n`, bin `k`; `Ymax(n−1,k)` is the max-filtered compressed magnitude from the *previous* frame, bin `k`; and `HWR(x) = max(x, 0)` half-wave-rectifies the difference, so only *increases* in energy contribute to the sum. Summing the rectified per-bin differences across all bins produces one novelty value per frame. Only increases counting toward the novelty value is deliberate and load-bearing, not an arbitrary simplification: an onset is, by definition, an increase in spectral energy, and this same property is exactly why the technique family is unsuitable for offsets — see "Why offset detection does not use SuperFlux or any onset-detection technique," immediately below.
5. **Adaptive local peak-picking.** Within the search window, every frame that is a local maximum on the novelty function is tested against a *locally adaptive* acceptance threshold — not a single fixed global sensitivity value — described in full in "Adaptive local peak-picking," immediately below. Among the frames that pass, the one with the highest novelty value becomes the refined boundary.

**SuperFlux hop size and reported-boundary resolution.** The refined boundary is reported at whichever novelty-function frame the accepted peak (step 5) lands on — a discrete frame selection, not a continuous crossing the way the RMS mechanism's threshold crossing is, so there is no equivalent "point between two measurements" for a linear-interpolation step to locate. That makes `superFluxHopSeconds` (table, above) the entire quantization budget for stage 2's reported time, the direct SuperFlux-side analogue of what `analysisWindowHopMilliseconds` is for the RMS mechanism (2026-08-13). At the `0.01`s (`10`ms) default, this bounds quantization error to at most one hop — comfortably inside even the tightest 1-frame tolerance (`33.3`ms at `.fps30`/`.fps29_97NonDrop`/`.fps29_97Drop`) with better than 3× margin, the same order of margin the RMS mechanism's hop-only bound achieves before its own dB-domain interpolation is even applied. **Unlike the RMS mechanism, no second, interpolation-style step is added on top here.** A standard analogous technique exists in the onset-detection literature — parabolic/quadratic interpolation of the novelty peak across its immediate neighboring frames, fitting a small curve to locate a sub-frame peak position — and would tighten this bound further, but it is deliberately not adopted now: the existing >3× hop-only margin already clears the target with room to spare, so there is no presently-known gap for it to close, unlike the RMS case, where hop alone left no interpolation-free path that also handled a fully-custom, potentially coarser project hop. Per `CLAUDE.md` rule 7, this is added later only if the real-fixture hard-case tier (`ROADMAP.md` T8.3) ever finds the plain hop-bound margin insufficient in practice — not spawned speculatively now alongside a margin that already clears the bar.

**Adaptive local peak-picking — stage 2's direct parallel to stage 1's time-varying noise floor.** A single fixed global sensitivity value has the same category of limitation `noiseFloorReestimationIntervalSeconds` already exists to solve for stage 1 (above): the novelty function's baseline level and variance genuinely differ between a dense, loud passage and a sparse, quiet one, so one fixed value can't be well-tuned for both — too permissive and it over-triggers during busy passages (re-litigating exactly the vibrato/tremolo false-positive problem the max-filter step above already suppresses, via a different failure path), too strict and it misses real onsets during quiet ones. Peak acceptance is therefore made **locally adaptive**, per standard onset-detection practice (Bello et al. 2005, already cited above; consistent with the broader onset-detection-novelty-function family's standard adaptive-threshold approach): a candidate frame `n` is accepted only if both hold —

1. **Local maximum:** `novelty(n) ≥ novelty(n−1)` and `novelty(n) ≥ novelty(n+1)`, with at least one strict inequality (so a flat run of equal novelty values can't repeatedly qualify as "a peak").
2. **Clears the local adaptive threshold:** `novelty(n) > median(novelty, window) × superFluxAdaptiveThresholdMultiplier + superFluxAdaptiveThresholdOffset × peakNoveltyInSearchWindow`, where `median(novelty, window)` is the median novelty value over a window of length `superFluxAdaptiveThresholdWindowSeconds` centered on frame `n`, and `peakNoveltyInSearchWindow` is the single highest novelty value anywhere in the current stage-2 search window (`superFluxRefinementSearchWindowSeconds`) — the fixed reference `superFluxAdaptiveThresholdOffset`'s fraction is taken against, per that field's definition in the table above.

To give frames near the search window's own edges a well-formed, non-truncated local median rather than an asymmetric one computed from fewer samples than frames nearer the center get, the novelty function is actually computed over the search region padded by `superFluxAdaptiveThresholdWindowSeconds / 2` on each side — a small, still-bounded extension of stage 2's cost (proportional to one search window per candidate boundary, per "Signal chain," above — never a whole-file computation), not an exception to that boundedness.

**`superFluxOnsetSensitivity` is retired outright, not kept alongside these three fields.** A single global sensitivity value and a locally-adaptive threshold are two different, non-composable models of the same decision (accept vs. reject a candidate peak) — keeping both would leave it ambiguous which one actually governs acceptance, or require them to somehow combine, neither of which is a real design worth having. The adaptive threshold is the strictly more capable replacement (it degrades gracefully to a roughly-fixed threshold on a novelty function with genuinely uniform baseline level and variance, which is exactly the case a fixed global value was already adequate for), so there is no case where the old field was doing something the new fields can't.

**This does not replace stage 1 and does not run standalone** — it only ever refines a boundary stage 1 has already roughly located, narrowing an arbitrary level-crossing point down to the actual moment of musical/spectral change. **Fallback:** if no candidate frame clears the adaptive threshold anywhere within the search window (e.g. a steady tone with no meaningful spectral change crossing the RMS threshold), stage 2 leaves the stage-1 boundary unchanged rather than relocating it to a spurious or arbitrary peak — the same "fall back to the simpler, already-defined behavior when refinement is inconclusive" pattern `noiseFloorCalibrationMode`'s automatic-mode fallback already establishes, above.

**Scope, deliberately and permanently bounded to cue starts.** This stage refines *silence→sound* (cue-start) boundaries only, where SuperFlux's onset-detection strength directly applies. See "Why offset detection does not use SuperFlux or any onset-detection technique," immediately below, for cue *ends* — a structurally different problem this stage is never applied to, by design, not by current omission.

**Explicitly out of scope: speech/music discrimination and any ML-based/trained classification.** This app's audio imports are music-only — never dialogue or sound design — so there is no music-vs-speech ambiguity for `SilenceDetector` to resolve, and no classifier of any kind is needed. This was a real technique considered during the research that led to adding spectral-flux-based refinement, and deliberately ruled out as inapplicable to this app's actual input material — not an oversight. See `docs/DECISIONS.md`, 2026-08-13, for the full record of both the addition and this scope boundary.

**Why offset (cue-*end*) detection does not use SuperFlux, plain spectral flux, or any onset-detection technique — a permanent architectural boundary, not a gap to fill.** Step 4 above half-wave-rectifies away energy *decreases*, keeping only increases, because that is definitionally what an attack transient is — this is not an arbitrary choice that could simply be flipped for offsets. Applying the same class of technique to find where a cue *ends* has two options, and both fail: dropping the rectification turns the novelty function into a generic "any spectral change, in either direction" detector, which loses the entire vibrato-suppression benefit this design exists for (a vibrato-driven energy *decrease* would then false-positive exactly like an unsuppressed increase would); inverting the rectification to look specifically for *decreases* still fails, because the largest spectral/energy decrease in a decaying musical passage occurs at the **start** of the decay — the moment the direct sound stops and the mix transitions into its reverb/release tail — not at the point the tail has decayed into inaudibility, which is where a human editor actually marks a cue's end. Flux-based novelty functions would therefore reliably mark cue ends too early, at the reverb-tail's onset rather than its perceptual end. This is a documented, structural limitation of onset/flux-based methods applied to offsets, not something tunable away by adjusting sensitivity or search-window parameters: general onset-detection surveys treat offset detection as a substantively different, less-developed problem not solved by the same techniques — see Bello, Daudet, Abdallah, Duxbury, Davies & Sandler, "A Tutorial on Onset Detection in Music Signals," *IEEE Transactions on Speech and Audio Processing*, 2005, cited here as a general onset-detection tutorial that makes this onset/offset distinction, not as a dedicated offset-detection study (no such study is being cited as if it were one).

Offset detection instead uses — confirmed here, explicitly, as the correct and unchanged approach — the existing two-threshold reverb-tail mechanism described in "Reverb tails," immediately below. That mechanism deliberately isn't a spectral/novelty technique at all: it tracks the same windowed-RMS values stage 1 already computes — now interpolated to sub-hop precision per "RMS time resolution and threshold-crossing interpolation," above, so lacking a SuperFlux-equivalent second stage doesn't mean lacking adequate time resolution — applying a second, *stricter* absolute-dB reference level than the main `silenceThresholdDb` gate, so a slowly-decaying tail can't extend a cue's measured end by an implausible amount, while a tail that decays into and stays in genuine silence is still correctly absorbed into the preceding cue's duration. Whichever comes first ends the candidate-tail state: (a) the level has stayed continuously below the stricter reference (`silenceThresholdDb − tailToleranceDb`, i.e. `tailToleranceDb` further down than the main threshold) for longer than `tailCapSeconds` — both already numerically defined in the table above (`6.0` dB, `2.0` s) — at which point the cue's end is hard-truncated to the point that stricter threshold was first crossed; or (b) the level rises back above the stricter reference before either condition is met, which is effectively a new onset — in which case the provisional tail-truncation candidate is simply abandoned and ordinary stage-1 sustained-silence logic continues, absorbing the region back into the ongoing cue rather than truncating anything, since it never sustained qualifying silence. This two-threshold design is a deliberately simple, non-adaptive proxy for a decaying reference curve tracking the tail's energy — not a continuously-adaptive envelope follower modeling the tail's actual decay shape, which "Reverb tails," below, already rules out as "a much harder DSP problem than this contract calls for" — and it remains, unchanged by this pass, the correct mechanism for offsets specifically.

**Stated plainly, for any future session: onset and offset detection are two genuinely different problems, solved by two different mechanisms, in this codebase.** Don't "simplify" this by unifying them onto one shared detector — doing so would silently reintroduce the "cue ends land at the reverb tail's onset, not its perceptual end" failure this section exists to rule out.

**Reverb tails.** This is the mechanism that governs cue *ends* — see "Why offset detection does not use SuperFlux or any onset-detection technique," above, for why this two-threshold approach, not a spectral/novelty technique, is the deliberate and permanent choice for offsets. A decaying tail after a musical passage ends can sit above a naively-chosen threshold for a while, which would otherwise delay gap detection and push a cue's measured end later than where the audible "music" really stopped. Two things bound this, deliberately without attempting perceptual/spectral tail modeling (a much harder DSP problem than this contract calls for):

1. Because a boundary requires *sustained* silence (`minimumSilenceDurationSeconds`) rather than a single below-threshold instant, a tail that decays into real silence and stays there is naturally absorbed into the *preceding* cue's measured duration — its end boundary sits at the start of the qualifying silence run, tail included. This is treated as correct, not a bug: the tail was audibly part of that work's use.
2. To stop a slowly-decaying tail from extending a cue's measured end by an implausible amount, a second, stricter threshold applies during a candidate tail: if the level has been continuously below `silenceThresholdDb − tailToleranceDb` (i.e. `tailToleranceDb` further down than the main threshold) for longer than `tailCapSeconds`, the cue's end is hard-truncated to the point that stricter threshold was first crossed — located via the interpolation described in "RMS time resolution and threshold-crossing interpolation," above, not merely rounded to the nearest RMS window — rather than waiting for the full decay to cross the main (less strict) threshold.

As with every detected boundary, this is a starting point for the editor, not a guaranteed-final value — the user can always adjust it.

**Borderline/flickering regions.** A region hovering right at the threshold (classic noise-gate "chatter") is handled by the same sustained-duration requirement as ordinary gap detection (`minimumSilenceDurationSeconds`), not a separate hysteresis threshold — a region must remain classified as silence *continuously* for the full minimum duration to register as a gap at all, which already suppresses single-window or short-burst threshold crossings without a second configurable value.

**Boundary accuracy target: 1 frame, not a fixed time value.** A detected boundary (silence-detected or embedded-marker-confirmed) must land within **1 frame of the project's configured `Setup.timecodeFrameRate`** (§4.9) of the true boundary — expressed in frames, deliberately, rather than as a fixed millisecond/sample number, because one frame is a different duration at different frame rates (§4.9's "Real FPS" column: `1/24s` at `.fps24`, `1/25s` at `.fps25`, `1/29.97s` at `.fps29_97NonDrop`/`.fps29_97Drop`, `1/30s` at `.fps30`) and this is a display-timecode accuracy guarantee, not a signal-processing one. `SilenceDetector` converts this into a sample-count tolerance at run time from the `AudioAsset`'s actual sample rate and the configured `TimecodeFrameRate`'s real FPS (`sampleTolerance = round(sampleRate / realFPS)`) — never a hardcoded sample-count or millisecond constant, since either would silently stop matching "1 frame" the moment a project uses a different sample rate or frame rate than whatever value was hardcoded. See `docs/DECISIONS.md`, 2026-08-12, for why frames rather than fixed time, and for this contract's two-tier test coverage (synthetic clean-transition buffers plus a hand-verified real-audio fixture library covering fade-ins, quiet-under-ambient mixes, and short non-silent gaps — cases a synthetic buffer alone doesn't exercise).

**How each boundary type actually achieves this tolerance.** For cue *starts*, this target is met by SuperFlux's stage-2 refinement (above), which reports the boundary at the novelty function's own `superFluxHopSeconds` frame resolution (`10`ms default) — see "SuperFlux hop size and reported-boundary resolution," above, for the margin arithmetic (better than 3× inside the tightest `33.3`ms tolerance on the hop-quantization bound alone) — comfortably finer than any RMS window's own resolution. For cue *ends*, which have no equivalent second stage (see "Why offset detection does not use SuperFlux or any onset-detection technique," above), this target is met entirely by the RMS mechanism's own resolution — `analysisWindowHopMilliseconds`'s default (`10.0`ms) plus threshold-crossing interpolation, both in "RMS time resolution and threshold-crossing interpolation," above — which together bound RMS-mechanism error well inside even the tightest 1-frame tolerance (`33.3`ms at `.fps30`/`.fps29_97NonDrop`/`.fps29_97Drop`). This was a real, previously-unresolved gap, not an already-solved problem restated: before that addition, a 50ms RMS window with no documented hop or interpolation could not have reliably hit this target for cue ends.

**Combining with embedded markers.** This setting governs raw signal detection only; merging its output with `AudioAsset.embeddedMarkers` is `DetectCuesUseCase`'s job (`ROADMAP.md` D9/T9.1), using `embeddedMarkerMergeToleranceSeconds` from this same settings value so the whole detection pipeline is configured from one place. Rule: an embedded marker is always authoritative. A silence-detected boundary within `embeddedMarkerMergeToleranceSeconds` of an embedded marker is treated as confirming that marker, not as a second, competing detection — it does not produce a separate candidate. Two silence-detected boundaries (no marker involved) within the same tolerance of each other are merged into one.

**Re-running detection and manually-adjusted cues.** Re-running `DetectCuesUseCase` warns before discarding any `Cue` not sourced as `.detectedFromAudio` — `.embeddedMarker` and `.manual` cues are protected, `.detectedFromAudio` cues are freely regenerated. This is precise, not incomplete, *because* of §4.19's reclassification rule: the moment a user edits any field of a `.detectedFromAudio` cue (repositioning its `startTimecode`, correcting its duration, anything), its `source` becomes `.manual` as a direct side effect of that edit — so it is automatically protected by this same rule from that point forward, with no separate "was this .detectedFromAudio cue subsequently touched by a human" check required. A `.detectedFromAudio` cue the user has looked at and left unchanged is still freely discardable on re-run, which is correct: the user hasn't actually confirmed or corrected anything about it yet.

**Known gap:** this schema doesn't yet support a per-import override distinct from the app-wide default (e.g. "use different silence settings for this one unusually noisy production"). `ImportAudioUseCase`/`DetectCuesUseCase` can already accept an `AnalysisSettings` value directly at the call site without a schema change — whether that becomes user-facing UI (persisted per-`Project` vs. one-shot per-run) is a product decision for `ROADMAP.md` D9 (Cue Detection), not resolved here.

### 4.12 Referential Integrity for `Person`/`Label` (delete guard)

`Party.person(Person.ID)` / `.label(Label.ID)` are bare `UUID` references into `Project.people`/`Project.labels` — there is no SwiftData `@Relationship` cascade/nullify behind them (Domain-layer types don't know about SwiftData at all; see `CLAUDE.md`). Without an explicit rule, deleting a `Person`/`Label` that's still referenced would silently orphan every place it's used, with no compiler or runtime error.

**Rule: deletion is blocked, never cascaded, never nulled, whenever a reference exists.**

A dedicated Use Case — `DeleteRightHolderUseCase`, exposing `deletePerson`/`deleteLabel` methods (built at `ROADMAP.md` D3/T3.3, as the shared-Use-Case option this section originally left open) — is the *only* sanctioned way to remove a `Person`/`Label` from `Project.people`/`Project.labels`. Before deleting, it scans every `Party`-typed field reachable from the `Project`, plus `Settings.defaultDeclarant`:

- `Setup.producer`
- `Setup.directorOrPrincipal`
- `Setup.declarant`
- `Settings.defaultDeclarant` (app-level, not project-scoped, but still a live reference)
- every `Cue.rightHolders[].party`, for every `Cue` in `Project.cues`

If any reference is found, the Use Case returns a typed failure listing exactly where:

```swift
enum PartyReferenceLocation: Equatable {
    case setupProducer
    case setupDirectorOrPrincipal
    case setupDeclarant
    case settingsDefaultDeclarant
    case cueRightHolder(cueID: Cue.ID)
}
```

so the calling ViewModel/View can tell the user precisely what to edit first, rather than showing a generic "can't delete" message. Deletion proceeds only once the returned reference list is empty — the user must reassign or remove every reference first. This is a hard block by design: nullifying a required field like `Setup.declarant`, or silently dropping the last remaining entry from a required list like `Setup.producer`, would each create an invalid `Setup`, and cascade-deleting a `CueRightHolder` row would silently break that `Cue`'s 100%-share invariant (§4.6) without the user's knowledge — all are worse outcomes than refusing and explaining exactly why.

### 4.13 `PartyResolver`

Resolving a `Party` value into something displayable (a name, an address) requires looking it up against `Project.people`/`Project.labels` — every screen that shows a right-holder needs this. To avoid that scan-and-match logic being reimplemented slightly differently in every ViewModel, it lives in exactly one place: `PartyResolver`, a stateless, pure (no I/O, no async) type in `ACCore/Models/PartyResolver.swift` — a plain function/namespace, not a Use Case, since it has no Repository dependency and nothing to orchestrate (see `CLAUDE.md` Naming Conventions).

```swift
enum PartyResolver {
    static func resolve(_ party: Party, people: [Person], labels: [Label]) -> ResolvedParty?
}

struct ResolvedParty: Equatable {
    let displayName: String        // "First Last" for a Person, or the company name for a Label
    let address: PostalAddress?    // nil if the referenced Person's address isn't set (Person.address is optional; Label.address is always present)
    let ipiNumber: String?
}
```

Returns `nil` only if the referenced `id` isn't found in either array — i.e. exactly the dangling-reference case §4.12's delete guard exists to prevent. Any caller that hits `nil` here, once §4.12 is correctly enforced everywhere deletion happens, indicates a bug, not a valid state to design UI around.

### 4.14 `Setup.totalMusicRuntime` — Source of Truth and Update Rule

`Setup.totalMusicRuntime` (§4.2) is a single persisted field — there is no separate "derived" shadow value; the field itself is both the exported value and the thing kept in sync. Ownership:

- **Source of truth:** the `Setup.totalMusicRuntime` field, always. It is what gets exported.
- **Update rule:** whenever `Project.cues` changes (add/edit/delete/reorder-with-duration-change) **and** `Settings.autoComputeTotalMusicRuntime == true`, the field is recomputed as `Σ cues[].duration` and written atomically as part of the same mutation — never as a separate, possibly-forgotten follow-up step.
- **Owning Use Case:** `UpdateCueUseCase` (planned for `ROADMAP.md` D10/T10.1) is responsible for triggering this recompute after every Cue mutation it performs. The actual sum logic lives in exactly one place — a pure static helper, `RecalculateTotalMusicRuntimeUseCase.recalculate(cues:) -> MediaDuration` — so it's computed identically everywhere it's needed, never copied.
- **Manual override:** when `Settings.autoComputeTotalMusicRuntime == false`, `UpdateCueUseCase` leaves the field untouched; it can then only be changed via `UpdateSetupUseCase` (an explicit user edit of `Setup` directly).
- **Toggling the setting:** flipping `autoComputeTotalMusicRuntime` from `false` → `true` immediately triggers one recompute via the same helper (invoked from the settings-update path, e.g. `UpdateSettingsUseCase`), so the field can't be left stale after re-enabling auto-compute. Flipping `true` → `false` leaves the current value as-is — it simply stops being overwritten going forward.

This resolves the original derived-vs-stored ambiguity by making the calculation a single, named, reusable piece of domain logic invoked from exactly two call sites (Cue mutation, settings toggle) — not two independent implementations of the same sum.

### 4.15 `WaveformPeaks` and `WaveformPeakBucket`

Resolves a gap flagged in an earlier revision of this document: `CLAUDE.md`'s folder structure names `ACDesignSystem/Components/WaveformView`, but nothing in the schema or the audio pipeline (`ROADMAP.md` D8) produced any data for it to render. This section is that missing piece.

**Representation: a fixed-size, downsampled min/max peak array — never raw or full-resolution sample data.** For each of a fixed number of time buckets spanning the whole file, `WaveformPeaks` stores the minimum and maximum normalized sample amplitude reached in that bucket. Min/max-per-bucket (not average/RMS) is the standard waveform-rendering technique specifically because it preserves visible transients (a single sharp peak) that an averaging approach would smooth away.

| Field | Type | Notes |
|---|---|---|
| `id` | `UUID` | |
| `audioAssetID` | `AudioAsset.ID` | which `AudioAsset` this summarizes |
| `resolution` | `Int` | bucket count; fixed at `4096` for the persisted overview (see below) |
| `buckets` | `[WaveformPeakBucket]` | length always equals `resolution` |

**`WaveformPeakBucket`:**

| Field | Type | Notes |
|---|---|---|
| `min` | `Float` | normalized amplitude, `-1.0...1.0` |
| `max` | `Float` | normalized amplitude, `-1.0...1.0` |

Conformances (both types): `Equatable`, `Hashable`, `Sendable`. No `Codable` — see `CLAUDE.md`, "Domain Model Value-Type Conformances."

**Memory bound.** `resolution` is fixed regardless of file length — a 3-hour file and a 3-minute file both produce exactly 4096 buckets. At 2 × `Float` (8 bytes) per bucket, the persisted overview is `4096 × 8 = 32,768` bytes — trivially safe to hold fully in memory or persist, independent of source file size. This is what lets `WaveformPeaks` exist as a plain `ACCore` value type without violating the "never load a full WAV into memory" constraint, the same way `AudioAsset`'s metadata-only invariant does (§4.10).

**v1 simplification: mono mixdown, not per-channel.** Multi-channel source audio is summed to a single mono trace before peak extraction. A dual-trace (or per-channel) stereo waveform display is a real, plausible future enhancement, but not designed as part of this change — see §6.

**Generation.** `ACAudioKit`, behind `AudioAnalysisRepository` — the same layer and protocol responsible for everything else audio-related, per `CLAUDE.md` rule 3 ("new audio analysis techniques are added inside `ACAudioKit`, behind the existing `AudioAnalysisRepository` protocol"). Computed via the streaming reader (`ACAudioKit/Streaming`) in bounded chunks: each chunk contributes to whichever bucket(s) its sample range maps to, via a vDSP min/max reduction (`vDSP_minv`/`vDSP_maxv` or equivalent) per `CLAUDE.md`'s "no hand-rolled sample loops" rule — never a second, separate full-file read distinct from the pass import/analysis already performs.

**Ownership and lifecycle: generated once, automatically, right after import.** `GenerateWaveformPeaksUseCase` (`ACCore/UseCases/`) runs immediately after `ImportAudioUseCase` completes, producing the fixed-resolution overview and persisting it to `Project.waveformPeaks` (§4.1) — not lazily generated on first view, so the editor's waveform is never shown mid-computation for a file the user already finished importing.

**Progressive rendering for long files: two-tier, not a single resolution and not a full mip-map pyramid.**

1. **Overview** — the persisted `WaveformPeaks` described above, one fixed 4096-bucket summary of the entire file. This is what renders the full-timeline view. For a 3-hour file, 4096 buckets means roughly 2.6 seconds per bucket — coarse, but that's expected and correct for a full-file overview; it's not meant for boundary-level precision.
2. **On-demand detail** — when the editor UI is zoomed into a specific time range (e.g. adjusting a cue boundary) **via `WaveformView`'s own horizontal-zoom gesture, `ROADMAP.md` D9/T9.3** (this section previously assumed a zoom trigger existed without specifying where it lived or what actually invoked it — that gap is closed by T9.3's zoom mechanism, below), `GenerateWaveformDetailUseCase` computes peaks for just that visible range, at a resolution supplied by the caller (driven by the actual pixel width of the zoomed-in view, not a fixed constant). This is deliberately **not persisted or cached** — a bounded time-range read via the streaming reader is cheap even against a 3-hour source file, and caching zoom-dependent results would be speculative complexity for a cost that's already negligible (see §6 for this as an explicit non-goal, not an oversight).

A full multi-resolution mip-map (as some professional DAWs build) was deliberately not designed — two tiers (bounded overview + on-demand bounded detail) covers this app's actual editing workflow (confirm/adjust cue boundaries, not sample-accurate waveform editing) without the added complexity of maintaining a resolution pyramid.

**What `WaveformView` (`ACDesignSystem`) itself consumes.** Per `CLAUDE.md`'s Design System rules, `ACDesignSystem` has zero knowledge of domain types — so `WaveformView` never takes a `WaveformPeaks` directly. It takes a design-system-local, domain-free `WaveformDisplayData` (defined in `ACDesignSystem`, not `ACCore`) — the same "local adapter struct" pattern already established for `CueTableView`'s row protocol. A Feature-layer mapper (in `ACFeatures`) converts `WaveformPeaks`/detail-region buckets into `WaveformDisplayData` at the point a screen renders it. See `CLAUDE.md`, Design System section, for the adapter type's shape.

`WaveformView` also has an **interactive mode** — cue-boundary markers overlaid on the waveform, draggable to reposition a `Cue`'s `startTimecode` — used for manual cue correction (§4.19). This still takes no domain type: boundary positions cross the component boundary as plain `Double` offsets via closures (e.g. `onBoundaryDragged: (Int, Double) -> Void`), with the `ACFeatures`-layer mapper converting to/from `Timecode` at the call site, same as the display-only path above. `ROADMAP.md` D9/T9.3 is where `WaveformView` is actually built — it wasn't previously scoped as a buildable component anywhere in the roadmap despite being named in `CLAUDE.md`'s folder structure since the project's first commit.

**Horizontal (time-axis) zoom — now explicitly scoped, `ROADMAP.md` D9/T9.3.** `WaveformView`'s interactive mode gains a zoom gesture (trackpad pinch, plus +/− controls as a fallback) that narrows/widens the visible time range — the actual trigger the "on-demand detail" tier (above) always assumed existed without specifying where it lived. Crossing the `ACDesignSystem` boundary follows the same closure-based, domain-free pattern as the drag gesture: a plain `visibleRangeSeconds: ClosedRange<Double>` value, never a domain type. That state is owned by a new `ACFeatures`-layer `CueDetectionReviewViewModel` — not `WaveformView` itself, consistent with `CLAUDE.md`'s MVVM rule that Views hold no business/orchestration state — which calls `GenerateWaveformDetailUseCase` for the narrowed range once it passes the point the persisted overview can no longer usefully serve it, at a resolution driven by the view's actual pixel width, and maps the result to a replacement `WaveformDisplayData` via the same adapter pattern the overview tier already uses. **A boundary marker's drag-offset math must be computed against the current `visibleRangeSeconds` window's pixel-to-time mapping, not the full-file range, whenever zoomed in** — an implementation that keeps using the full-file mapping while zoomed would silently reposition a dragged boundary to the wrong offset, by exactly the zoom factor's error, with no visible sign of failure short of checking the resulting `Timecode`. See `ROADMAP.md` D9/T9.3's dedicated Acceptance Criterion for this specifically, and `docs/DECISIONS.md`, 2026-08-14, for why this was added as a scope correction ahead of D9 rather than discovered mid-implementation.

**Horizontal pan — the necessary complement to zoom, found in the same review that found zoom itself missing (`docs/DECISIONS.md`, 2026-08-14).** A zoom control with no way to move the visible window afterward is incomplete: once `visibleRangeSeconds` is narrower than the file's full duration, `WaveformView` gains a pan mechanism that shifts that same range left/right at **constant width** — a two-finger trackpad scroll as the primary gesture (the idiomatic macOS convention for panning a zoomed view), plus click-and-drag on empty waveform background as a mouse-compatible fallback, mirroring zoom's own "primary gesture + fallback control" shape (pinch + buttons). **Disambiguation from the pre-existing boundary-marker drag — both are horizontal drags on the same component:** a drag gesture that starts within a boundary marker's hit-region is *always* treated as marker-reposition, by hit-testing precedence, never pan, regardless of zoom state; and once a marker-drag is in progress, a concurrent pan input (e.g. a scroll event arriving mid-drag) is ignored for the duration of that drag rather than being allowed to interleave. A **grab-cursor affordance** (open hand while idle over a zoomed, non-marker area; closed/grabbing while actively panning) is shown only when `visibleRangeSeconds` is narrower than the file's full duration *and* the pointer isn't over a marker's hit-region — no affordance at all while unzoomed, since there's nothing to pan (the same cursor-communicates-affordance pattern `ROADMAP.md`'s D6 hover-cursor fix already established in this codebase). Panning is clamped so `visibleRangeSeconds` can never extend past `[0, fileDuration]`. **Panning into a not-yet-fetched time range triggers the same debounced `GenerateWaveformDetailUseCase` call zoom-narrowing already does** (above) — sliding the window is not exempt from needing on-demand detail merely because its width didn't change.

**Vertical (amplitude) zoom — a pure rendering transform, no new data.** `WaveformView` also gains a vertical-scale control (e.g. a corner slider) that multiplies each drawn peak's height by a `verticalScale: Double` gain factor at draw time, applied directly against `WaveformPeakBucket`'s existing normalized `-1.0...1.0` `min`/`max` values (above) — no new field, no repository/Use Case involvement, and no interaction with the horizontal-zoom/on-demand-detail mechanism described above. **Deliberately ephemeral, per-screen state** — held locally by `WaveformView`/its host, reset to a default scale every time the view is reopened, never persisted to `Project` or `UserDefaults`. This was confirmed directly with the project owner rather than assumed either way (`docs/DECISIONS.md`, 2026-08-14), and mirrors other purely-visual, non-business UI state elsewhere in this app (e.g. `AppState.selectedSection`, `CLAUDE.md`'s Document & Window Model) rather than being treated as data worth saving.

### 4.16 `CueSheetPageLayout` — the shared preview/export layout model

See `CLAUDE.md`'s Export Architecture section for why this exists (in short: the on-screen A4 preview and the exported PDF must be pixel-identical, which requires computing layout exactly once, not twice). The types:

| Type | Shape | Notes |
|---|---|---|
| `CueSheetPageLayout` | `{ pageIndex: Int, pageCount: Int, elements: [CueSheetLayoutElement] }` | one page's worth of fully-positioned content |
| `CueSheetLayoutElement` | `{ frame: LayoutRect, content: LayoutElementContent }` | one positioned piece of content on a page |
| `LayoutRect` | `{ x: Double, y: Double, width: Double, height: Double }` | a plain, Foundation-only geometry primitive — deliberately **not** `CGRect`. `ACCore` stays Foundation-only per `CLAUDE.md` rule 1; `CGRect` is a Core Graphics type. Each rendering backend (Core Graphics for the real PDF, SwiftUI for the on-screen preview) converts `LayoutRect` to its own native geometry type at the point of drawing — the same adapter-at-the-edge pattern as `WaveformDisplayData` (§4.15) |
| `LayoutElementContent` | `enum { text(String, font: LayoutFontSpec), rule(LayoutRuleSpec) }` (sketch only) | the exact case set (table cells, borders, logos, etc.) is real visual-design work for `ROADMAP.md` D11/T11.2, not fixed by this architectural change — this section commits to the *mechanism* (one computed layout, two consumers), not the SUISA form's pixel-perfect visual design |

Conformances: `Equatable`, `Hashable`, `Sendable` (`LayoutFontSpec`/`LayoutRuleSpec` follow the same pattern — plain Foundation value types, not designed field-by-field here). No `Codable` — see `CLAUDE.md`, "Domain Model Value-Type Conformances."

Who computes it: `ExportRepository` (`ACExport`, Data layer) — it's the one place with Core Text available for real text measurement and line-breaking, which pagination (5 works/page main form, 4/page continuation, per §2.1) genuinely depends on getting right. Pure Foundation code cannot compute accurate text layout; this is why layout *computation* is a Data-layer responsibility even though the resulting *value* is a plain `ACCore` type.

Who consumes it: both the real PDF renderer (`PDFCueSheetRenderer`, `ACExport` — draws it with Core Graphics `PDFContext` + Core Text) and the on-screen preview View (`ACFeatures` — obtains the same value via a Use Case wrapping `ExportRepository`, then draws it with SwiftUI, e.g. `Canvas`). Both draw the *identical* precomputed frames and text; neither re-derives layout independently.

**`CueRightHolder` rows with `role == .performer` (§4.4) are never included when this layout is computed for a Cue's right-holder block.** The physical WA Film form's right-holder block has no slot for a 5th role (the C/A/AR/E legend is composer/author/arranger/publisher only) — `ExportRepository`'s layout computation filters `.performer` rows out before laying out that block, the same way `ValidateCueRightHolderSharesUseCase` excludes them from both share sums (§4.4, §4.6). Performer rows still appear in the XLSX export, which isn't constrained by this fixed physical layout.

### 4.17 `ProgressUpdate` and `OperationProgress<Success>`

The shared progress-reporting shape used by every long-running operation — see `CLAUDE.md`'s "Long-Running Operations: Progress & Cancellation" section for the full rationale and which operations use it.

```swift
public struct ProgressUpdate: Sendable, Equatable {
    public let fractionCompleted: Double   // 0.0...1.0
    public let message: String?             // optional human-readable status
}

public enum OperationProgress<Success: Sendable>: Sendable {
    case progress(ProgressUpdate)
    case completed(Success)
}
```

Both are plain `ACCore` value types (`ACCore/Models/`) — Foundation-only, no dependency on `Progress` (Foundation's KVO-based class) or any other framework. A Repository/Use Case method that reports progress returns `AsyncThrowingStream<OperationProgress<T>, Error>`, where `T` is whatever that operation ultimately produces (`AudioAsset` for import, `[Cue]` for detection, `WaveformPeaks` for the waveform overview, a file `URL` for export).

### 4.18 Cue Deletion: Save Timing, Confirmation, and Undo

Resolves a gap in an earlier revision of this document: `UpdateCueUseCase`'s delete path was specified as a data operation (`ROADMAP.md` D10/T10.1), but nothing specified the save timing this operation actually uses, or the interaction contract around it (confirmation? undo?).

**Save timing: structural cue mutations are never debounced — they save immediately.** `CLAUDE.md`'s "Autosave is debounced, not triggered on every keystroke/edit" rule was written with continuous field-editing in mind (typing a title, adjusting a percentage share) and is correct for that case — debouncing exists specifically to avoid a save-per-keystroke storm. Deleting, adding, or reordering a `Cue` is a different shape of action: discrete, complete the instant it happens, with nothing further to type. Debouncing a delete would mean a deleted row could still exist in persisted state for up to the debounce interval, which is exactly the gap that makes "does Review & Export update immediately" a real question rather than a given. **Resolution:** `UpdateCueUseCase`'s add/delete/reorder operations write through to `ProjectRepository` immediately (still `async`, just not debounce-delayed) — only continuous field-level edits within a `Cue` remain debounced. `CLAUDE.md`'s Performance Considerations section is updated to state this distinction explicitly, not left as a blanket "autosave is debounced" claim that this section would otherwise contradict.

**Live propagation to Review & Export.** Because the delete write is immediate, it republishes into `ProjectRepository`'s live-observation stream (`CLAUDE.md`, "Single Source of Truth") immediately too — `ReviewViewModel`, subscribed to that same stream, observes the updated `Project.cues` (and re-runs `ValidateCueSheetUseCase` against it) without `CueSheetEditorViewModel` and `ReviewViewModel` needing any direct reference to each other, and without either performing an explicit "refresh." This is verified, not just asserted: `ROADMAP.md` D11 specifies a concrete test constructing both ViewModels against the same fake `ProjectRepository` and asserting the propagation actually happens end-to-end.

**Confirmation: none. Deletion is a direct, single-step action, regardless of how many `CueRightHolder` entries are attached.** A confirmation dialog is the wrong safety mechanism for a common, easily-reversible action — Apple's HIG stance on this (no confirmation for actions with a real, discoverable undo path) applies directly here, and adding one anyway would be redundant friction on top of the undo mechanism below, not additional safety. Deleting a `Cue` deletes its `[CueRightHolder]` entries atomically as part of the same operation — there is no scenario where a `Cue` is deleted but its right-holders survive orphaned, so there's no additional risk from "how many right-holders were attached" to confirm against.

**Undo: yes, via standard ⌘Z, through the environment `UndoManager`.** At the point of deletion, the ViewModel registers an inverse action (re-insert the deleted `Cue`, with its `[CueRightHolder]` entries, at its original index) with the window's `UndoManager` — the standard SwiftUI/AppKit mechanism, not a bespoke undo stack. This is what makes "no confirmation dialog" the correct call rather than a corner cut: the safety net is real and standard, not assumed.

### 4.19 Manual Cue Correction

Resolves a gap in an earlier revision of this document: `AudioAsset.embeddedMarkers` had no editing path, `AudioAsset` is documented as an immutable derived snapshot (§4.10), and nothing let a user correct a detection `DetectCuesUseCase` got wrong.

**Architectural home: correction happens entirely at the `Cue` level. `AudioAsset`/`EmbeddedMarker` are never mutated, and this is not a workaround — it's the correct model.** `EmbeddedMarker` is a factual record of the source WAV file's contents (§4.10); `Cue` is the app's editable interpretation, already built from that raw data plus signal analysis by the time a user would ever want to correct something (`DetectCuesUseCase`, `ROADMAP.md` D9/T9.1, per §4.11's "Combining with embedded markers" merge rule). Once that merge has happened, "correcting a misjudged detection" and "editing a `Cue`" are the same action — there is no separate "marker" concept left to correct independently, and inventing one would duplicate `Cue`'s already-existing edit/delete/add capability (`ROADMAP.md` D10/T10.1's `UpdateCueUseCase`) for no benefit, which is exactly what `CLAUDE.md` rule 7 (no premature abstraction) argues against.

**Three required capabilities, and where each lives:**

1. **Add a cue the analysis missed entirely.** A "+ Add Cue" action in `CueTableView`/`CueSheetEditorView` (`ROADMAP.md` D10/T10.2), creating a new `Cue` via `UpdateCueUseCase`'s existing add path with `source: .manual` set at creation (not requiring the reclassification rule below, since it was never anything else). No new Use Case — this is the same general-purpose "add a cue" capability the Cue Sheet Editor needs regardless of whether the motivating reason is "detection missed one" or "I just want to add a work."
2. **Remove one the analysis wrongly created.** The exact same delete control specified in §4.18 (the X button in `CueTableView`) — no separate "reject detection" UI. A wrongly-detected cue is simply a cue to delete, like any other.
3. **Reposition a cue's timecode.** Two entry points, both writing through `UpdateCueUseCase`'s existing edit path (which triggers the §4.3 reclassification rule — the cue's `source` becomes `.manual` the moment either is used):
   - **Direct timecode field edit** — a text field bound to `Cue.startTimecode` in `CueRowDetailView` (`ROADMAP.md` D10/T10.2), formatted/parsed via `Timecode`'s existing `HH:MM:SS:FF` formatting and `init?(components:frameRate:)` parsing (§4.9) — invalid input (including invalid drop-frame timecodes) is rejected by that same, already-implemented and tested initializer, not a new validation path.
   - **Drag in the waveform view** — `WaveformView` (`ACDesignSystem`) is extended to render cue-boundary markers overlaid on the waveform and support a drag gesture on them. Per `CLAUDE.md`'s Design System rule (components take no domain types, only closures/bindings), the drag interaction crosses the `ACDesignSystem` boundary as a plain callback (`onBoundaryDragged: (boundaryIndex: Int, newOffsetSeconds: Double) -> Void`, or equivalent) — an `ACFeatures`-layer mapper converts the resulting offset to/from `Timecode` at the point it's applied via `UpdateCueUseCase`, the same adapter-at-the-edge pattern already established for `WaveformDisplayData` (§4.15). This is genuinely new work — `WaveformView` was named in `CLAUDE.md`'s folder structure from the project's start but never actually scoped as a buildable component anywhere in `ROADMAP.md` until this section — see `ROADMAP.md` D9/T9.3 for where it's now built, including this interactive mode alongside the plain display mode §4.15 already specifies.

   Dragging adjusts only the one cue's `startTimecode`/`duration` being dragged — it does not automatically ripple onto a neighboring cue's boundary. `Cue.duration` is stored independently of `startTimecode` (§4.3: duration is "total duration this work is used," not derived from "next cue's start minus this cue's start"), so cues are not modeled as a contiguous timeline requiring one drag to imply another. If the user needs to adjust an adjacent cue too, they adjust it independently. This is a deliberate scope limit, not an oversight — a contiguous-timeline ripple model is real additional complexity nothing in this app's actual workflow currently needs.

**Where this is reachable from — not the transient detection-progress view.** `CueDetectionProgressView` (`ROADMAP.md` D9/T9.2) is a progress indicator for the duration of the detection run itself; it is not where correction happens, since showing "detection is running" and "let me review what it found" are different moments in the workflow, not one screen. The waveform-based review/correction surface built in D9/T9.3 and the direct-field/table-based editing in D10 are both reached from the Cue Sheet Editor, once `Project.cues` has actually populated — one place to edit cues, not two.

## 5. Scope of This Document

This document is now fully self-contained: every domain type referenced anywhere in `CLAUDE.md` (`AudioAsset`, `Timecode`, `TimecodeFrameRate`, `MediaDuration`, `AnalysisSettings`, `PartyResolver`, `WaveformPeaks`, `CueSheetPageLayout`, `OperationProgress`, etc.) is fully specified above in §4, not deferred to an external document. An earlier draft of this project referenced an "original architecture document" for `AudioAsset`/`Timecode`/`AnalysisSettings`; that document does not exist anywhere in this repository's history and has been superseded — §4 above is the sole authoritative source for all domain types going forward.

There is intentionally no separate persisted `CueSheet` type: the exportable cue sheet is the combination of `Setup` + `[Cue]`, assembled on demand by `ExportCueSheetUseCase` — introducing a distinct `CueSheet` model would duplicate data already owned by `Project`.

## 6. Known Gaps / Follow-ups

- The exact current revision of the SUISA WA Film form now has a concrete, dated revalidation checkpoint (§2.3) tied to `ROADMAP.md` D11/T11.3, rather than being an open-ended "should be reconfirmed" item with nothing forcing it to actually happen.
- SWISSPERFORM has no equivalent structured document to validate field-by-field against; §2.2's approach (shared identity fields, no fabricated "SWISSPERFORM cue sheet") should be revisited if SWISSPERFORM publishes a production-side reporting form in the future.
- IPI/CAE number fields are an AutoCue addition for disambiguation, not a literal field on the sourced paper form — acceptable, but worth confirming SUISA is fine receiving it as supplementary info if included in exports.
- `AnalysisSettings` has no per-import override mechanism yet, only an app-wide default (§4.11).
- `ROADMAP.md` has been fully restructured as of this revision (Deliverables D1–D17, replacing the flat M1–M34 milestone list) with every file path corrected to `Packages/ACFeatures/Sources/ACFeatures/...` — the `Features/...`-path staleness flagged in earlier revisions of this document is resolved. Treat `ROADMAP.md` as current going forward, not this note.
- `WaveformPeaks` (§4.15) is mono-mixdown only — no per-channel/stereo dual-trace representation. A real, plausible future enhancement, not designed here.
- `GenerateWaveformDetailUseCase` (§4.15) results are never cached across zoom interactions — always recomputed on demand (debounced/coalesced during a continuous gesture, per `ROADMAP.md` D9/T9.3, but never cached across separate zoom interactions). This line previously referred to a zoom trigger that didn't yet exist anywhere in the roadmap; `ROADMAP.md` D9/T9.3 now scopes the actual horizontal-zoom mechanism that invokes these calls (`docs/DECISIONS.md`, 2026-08-14). The no-caching decision itself remains deliberate (the cost is already negligible against a bounded time range), not an oversight; revisit only if a real performance problem shows up once T9.3 is built.
- `WaveformView`'s vertical (amplitude) zoom level (§4.15) is ephemeral, per-screen state only — never persisted per-`Project` or via `UserDefaults`. Confirmed directly with the project owner, 2026-08-14 (not assumed either way) — see `docs/DECISIONS.md`. Revisit only if real usage shows a persisted preference is actually wanted.
- `CueSheetPageLayout` (§4.16) fixes the *mechanism* for keeping preview and export in sync — the actual SUISA-matching visual design (exact fonts, column widths, table borders) is still unbuilt, real work for `ROADMAP.md` D11/T11.2.
- The `libxlsxwriter` dependency (`CLAUDE.md` rule 4) has been verified to compile, link, and produce a valid workbook via a real smoke test, **and** to work correctly under genuine kernel-enforced App Sandbox (a real ad-hoc-signed `.app` bundle carrying the actual sandbox entitlement — unauthorized writes were genuinely blocked, writes inside the sandbox container genuinely succeeded with correct output; see `docs/DECISIONS.md`). What remains unverified is narrower than "sandbox compatibility" in general: the real app's `NSSavePanel`-granted write flow specifically (dynamic, Powerbox-mediated access to a user-chosen destination) hasn't been tested, only the baseline container-write case has. Confirmed at `ROADMAP.md` D15/T15.2, once a real signed app target with real entitlements exists, not deferred back to D11.
- The Progress/Cancellation contract (§4.17, `CLAUDE.md`) has no system-level integration (Dock icon progress, Finder progress, menu-bar activity) — deliberately deferred; Foundation's `Progress` could be layered on top of a `AsyncThrowingStream`-driven operation later without changing this contract, if that's ever actually wanted.
- CI (`.github/workflows/ci.yml`) exists as of `ROADMAP.md` D1. Its pinned Xcode version was flagged as unconfirmed against a live runner in an earlier revision of this document; it has since actually been run three times: the first two genuinely failed (once on `swift-tools-version` — 15.4's Swift 5.10 toolchain vs. a then-declared `6.1`; once on `.swiftformat`'s matching `--swiftversion` setting producing trailing commas in function calls that same Swift 5.10 compiler can't parse), both diagnosed from real CI logs and fixed by correcting the declared version to match the real floor rather than moving the Xcode pin. The third run, after both fixes, was watched to completion and was genuinely green (all three jobs). See `docs/DECISIONS.md` for the full sequence. Closed, confirmed by an actually-observed green run, not asserted.
- Manual cue correction (§4.19) has no ripple model onto neighboring cues when one boundary is dragged — deliberate, per §4.19's own reasoning, not an oversight; revisit only if the independent-fields model turns out to be a real usability problem once built.
- Waveform boundary-drag interaction (§4.15, §4.19) is specified at the architecture level (what crosses the `ACDesignSystem` boundary, which Use Case it writes through) but not at the interaction-design level (drag physics, snapping tolerance, visual affordance) — real work for `ROADMAP.md` D9/T9.3, not fixed by this architectural change.
- `Setup.beitrag`/`.exploitationTypes`/`.broadcastDetails`/`.timecodeStart` (§4.2, §4.2.3–§4.2.4) — added during `ROADMAP.md` D7 planning after being found missing from this schema — are currently treated as export-optional (render when present, don't block export when absent; `timecodeStart` is never exported at all — app-internal only, like `timecodeFrameRate`). **Whether `beitrag`/`exploitationTypes`/`broadcastDetails` are actually export-required, matching SUISA's real WA Film form, is unconfirmed** — check at `ROADMAP.md` D11/T11.3's SUISA revalidation checkpoint (§2.3) alongside the form-version re-verification already scheduled there, before `ValidateCueSheetUseCase` is implemented. See `docs/DECISIONS.md`.
- `Setup.seasonNumber`/`.episodeNumber`/`.episodeTitle` (§4.2) only support a single episode per `Setup`/`Project` — there is no way to declare a batch covering more than one episode (e.g. multiple Episode Titles for an Episode range) within one `Setup`. Found during `ROADMAP.md` D7's screen-reorder work when asked directly why no such UI exists: this isn't a SUISA-form gap (none of these three fields is on the physical form at all, so the form has no opinion either way) — it's a pre-existing app-internal schema limitation. The only current workaround is one `Project` per episode, matching this app's existing one-production-per-window model. Whether to support a multi-episode batch within a single `Setup` is an open product decision, not resolved here.
