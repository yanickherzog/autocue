# AutoCue — Application Specification

Status: data model and compliance target finalized. No UI or business logic implemented yet.

## 1. Purpose

AutoCue is a native macOS application that generates Swiss film/TV cue sheets from WAV audio files. It analyzes a production's audio (embedded markers plus signal analysis) to identify the musical works it contains, and produces a cue sheet compliant with the format SUISA (Swiss authors'/publishers' rights society) requires for royalty distribution, exportable as PDF and XLSX.

## 2. Compliance Target

### 2.1 SUISA — "Declaration of musical works for films and audiovisual productions" (WA Film)

This is the primary, binding target format. It is SUISA's own paper/PDF form (form codes `WA Film 2011-01` main form + `WA Film II 2011-01` additional-works continuation, obtained directly from suisa.ch), submitted to SUISA's Film Department to report the musical works contained in a production and how performance/broadcast and mechanical rights are split between right-holders.

Structurally, this form is **not** a US-style (ASCAP/BMI) scene-by-scene cue log with usage categories (Background Instrumental, Visual Vocal, Main Title, etc.) and in/out timecodes. It is a **rights-accounting declaration**: for each musical work used in the production, it records the work's title, duration of use, and every right-holder's role and percentage share of performance/broadcast rights and mechanical rights. AutoCue's data model follows this shape. Do not import US cue-sheet conventions into required fields.

The main form holds 5 musical works per page and paginates with a 4-per-page continuation sheet ("Additional works") beyond that — this is an export/layout concern, not a data-model concern; the domain model has no fixed limit on the number of Cues per Project.

### 2.2 SWISSPERFORM

SWISSPERFORM (Swiss neighboring-rights society for performers and producers) does **not** have an equivalent per-production cue-sheet document. Its audiovisual-participation reporting is performer-centric and self-service: each performer registers their own participation (film/episode title, series/season, director, production country/year, function/role, shooting days or takes, role weighting) directly through SWISSPERFORM's online portal, not through a document the production company fills in per-production the way SUISA's WA Film form works.

Consequently, AutoCue does not attempt to generate a "SWISSPERFORM cue sheet" — no such artifact exists in the same shape as SUISA's. What it does instead: the `Person` model carries an optional `swissPerformNumber`, and `Setup` carries the production-identity fields (series/season, director, country, language) that a performer would need when self-registering — so the data AutoCue already collects for SUISA can be reused/exported as reference information for SWISSPERFORM registration, without AutoCue claiming to produce an official SWISSPERFORM filing.

### 2.3 Open item to verify before submission-critical use

The form was sourced directly from suisa.ch (`WA Film 2011-01`). Form revisions are infrequent but possible — before relying on this for a real SUISA submission, confirm with SUISA (`filmproduction@suisa.ch`) that this is still the current version. This does not affect the architecture; only individual field/label wording would change if SUISA revises the form.

## 3. Functional Scope (data-model relevant)

1. Import a WAV file (up to ~3 hours) as a `Project`'s `AudioAsset`.
2. Detect candidate `Cue`s via embedded WAV markers and/or silence-gap analysis.
3. Let the user edit/confirm Cues and attach right-holder (`Person`/`Label`) information and rights shares.
4. Maintain a production-level `Setup` (the SUISA form header).
5. Validate the data set against SUISA's rules (100%-share sums, required attachments for certain roles).
6. Export the finished cue sheet as PDF (visually matching the SUISA form layout) and XLSX (tabular, one row per Cue/right-holder, for internal use and easy re-editing).

UI flows and use-case logic are out of scope for this document — see `CLAUDE.md` for architectural rules governing where that logic lives.

## 4. Data Schema

Types: `String`, `String?` (optional String), `Int`, `Decimal`, `Bool`, `Date`, `UUID`, `enum`, `Set<T>`, `[T]` (ordered array). `Duration` and `Timecode` are the value types already defined in the original architecture (frame/second-based, formatted `hh:mm:ss`).

### 4.1 `Project`

| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | `UUID` | required | |
| `name` | `String` | required | internal working name; may differ from `setup.title` |
| `createdAt` | `Date` | required | |
| `updatedAt` | `Date` | required | |
| `audioAsset` | `AudioAsset` | required | from original architecture, unchanged |
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
| `producer` | `Party` | **required** | "Producer (complete address)" | |
| `directorOrPrincipal` | `Party` | **required** | "Director / principal (commercials and Spots)" | form frames the label around commercials/spots but the field applies to all production types |
| `productionRuntime` | `Duration` | **required** | "Playing time of film or production" | |
| `totalMusicRuntime` | `Duration` | **required** | "Total music playing time" | default = sum of `cues[].duration`; user-overridable (see `Settings.autoComputeTotalMusicRuntime`) |
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
| `declarant` | `Party` | **required** | "Particulars of the declaring person or publisher" | |
| `declarationDate` | `Date` | **required** | "Date and signature" | defaults to export date |
| `attachmentTypes` | `Set<AttachmentType>` | optional | "Attachment(s)" | see 4.2.2; informational flags only — the app does not manage the physical attachments themselves |
| `otherAttachmentDescription` | `String?` | required iff `attachmentTypes` contains `.other` | "Other (please indicate)" | |

Not modeled as app-editable fields: "ISAN No" registration workflow beyond storing the string, and "Registration date/employee initials" (explicitly "to be completed by SUISA" on the form — SUISA-internal, never app-authored).

#### 4.2.1 `ProductionType` (enum, from the form's checkbox grid)

`.featureFilm`, `.shortFilmCinema`, `.tvFeatureFilm`, `.tvShotFilm`, `.series`, `.documentaryFilm`, `.tvBroadcast`, `.leadInStationID`, `.educationalFilm`, `.commercial`, `.corporateFilm`, `.videoClip`, `.multimedia`, `.other`

Modeled as a `Set` (not a single value) because the form presents independent checkboxes, e.g. a production could legitimately be both `.series` and `.tvBroadcast`.

#### 4.2.2 `AttachmentType` (enum)

`.score`, `.agreement`, `.soundOrVideoCarrier`, `.other`

### 4.3 `Cue`

Many per `Project`, ordered. One SUISA "musical work" entry.

| Field | Type | Required | SUISA form field | Notes |
|---|---|---|---|---|
| `id` | `UUID` | required | — | |
| `title` | `String` | **required** | "Title of Nth work" | |
| `workNumber` | `String?` | optional | "Work No" | "where known" |
| `duration` | `Duration` | **required** | "Playing time" / "Duration" | total duration this work is used in the production |
| `rightHolders` | `[CueRightHolder]` | **required, ≥1** | "Right-holder...with status" block | |
| `source` | `enum { embeddedMarker, detectedFromAudio, manual }` | optional, app-internal | — | not exported to the SUISA document; drives editor UI provenance display |
| `startTimecode` | `Timecode?` | optional, app-internal | — | not exported; SUISA wants usage duration, not on-screen position |
| `notes` | `String?` | optional, app-internal | — | not exported |

### 4.4 `CueRightHolder`

Sub-entity of `Cue`; one row per right-holder per work.

| Field | Type | Required | SUISA form field | Notes |
|---|---|---|---|---|
| `party` | `Party` | **required** | "Name, first name or publishing company" | |
| `role` | `enum { composer, author, arranger, publisher }` | **required** | legend: C / A / AR / E | |
| `performanceBroadcastShare` | `Decimal` (%) | **required** | "Performances Broadcasts (%)" | see 4.6 for cross-field validation |
| `mechanicalRightsShare` | `Decimal` (%) | **required** | "Mechanical rights (%)" | |
| `publishingContractAttached` | `Bool` | required iff `role == .publisher` | "(join copy of publishing contract)" | |
| `arrangementAuthorizationAttached` | `Bool` | required iff `role == .arranger` and the original work is still copyright-protected | form footnote on arrangements | |

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

**`Label`** (corporate right-holder: publisher, production company, broadcaster):

| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | `UUID` | required | |
| `name` | `String` | **required** | |
| `address` | `PostalAddress` | **required** | form mandates "complete address" wherever a company stands in |
| `ipiNumber` | `String?` | optional | publisher CAE/IPI number |
| `kind` | `enum { publisher, productionCompany, broadcaster, other }?` | optional, app-internal | not on the form; used only for UI grouping |

**`Party`** (reference type, not persisted independently):

```
enum Party {
    case person(Person.ID)
    case label(Label.ID)
}
```

Used for: `Setup.producer`, `Setup.directorOrPrincipal`, `Setup.declarant`, `Settings.defaultDeclarant`, `CueRightHolder.party`.

**`PostalAddress`** (shared value type): `street`, `postalCode`, `city`, `country` — all `String`, all required whenever a `PostalAddress` is present at all (i.e., "complete address" per the form means all four parts, not a bare name).

### 4.6 Cross-field validation rules (enforced in Domain Use Cases, not in the structs)

- Per `Cue`: `Σ rightHolders[].performanceBroadcastShare == 100%`.
- Per `Cue`: `Σ rightHolders[].mechanicalRightsShare == 100%`.
- `Setup.productionTypes` must be non-empty.
- `Setup.otherProductionTypeDescription` required iff `.other ∈ productionTypes`.
- `Setup.otherAttachmentDescription` required iff `.other ∈ attachmentTypes`.
- `CueRightHolder.publishingContractAttached` must be `true` before export iff `role == .publisher`.
- `CueRightHolder.arrangementAuthorizationAttached` must be `true` before export iff `role == .arranger` and the work is flagged as based on a still-protected original.
- Whether a failed rule **blocks** export or only **warns** is controlled by `Settings.shareValidationStrictness`.

### 4.7 `Settings`

App-level only; not part of the SUISA document.

| Field | Type | Notes |
|---|---|---|
| `defaultDeclarant` | `Party?` | pre-fills `Setup.declarant` on new projects |
| `defaultProductionCountry` | `String?` | |
| `exportLanguage` | `enum { de, fr, it, en }` | SUISA's form exists in all four Swiss/working languages |
| `autoComputeTotalMusicRuntime` | `Bool` (default `true`) | sums `cues[].duration` into `Setup.totalMusicRuntime` unless manually overridden |
| `shareValidationStrictness` | `enum { warnOnly, blockExport }` | |
| `defaultExportFormat` | `enum { pdf, xlsx, both }` | |
| `silenceThresholdDb` | `Double` | audio-analysis default, carried from the original architecture's `AnalysisSettings` |
| `minimumCueGapSeconds` | `Double` | audio-analysis default |

## 5. Relationship to the Original Architecture Document

`AudioAsset` and `Timecode` are unchanged from the initial architecture design and are not redefined here. There is intentionally no separate persisted `CueSheet` type: the exportable cue sheet is the combination of `Setup` + `[Cue]`, assembled on demand by `ExportCueSheetUseCase` — introducing a distinct `CueSheet` model would duplicate data already owned by `Project`.

## 6. Known Gaps / Follow-ups

- Exact current revision of the SUISA WA Film form should be reconfirmed with SUISA before production/compliance-critical use (§2.3).
- SWISSPERFORM has no equivalent structured document to validate field-by-field against; §2.2's approach (shared identity fields, no fabricated "SWISSPERFORM cue sheet") should be revisited if SWISSPERFORM publishes a production-side reporting form in the future.
- IPI/CAE number fields are a AutoCue addition for disambiguation, not a literal field on the sourced paper form — acceptable, but worth confirming SUISA is fine receiving it as supplementary info if included in exports.
