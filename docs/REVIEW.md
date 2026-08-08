# AutoCue — Review Log

An append-only log, one entry per completed `ROADMAP.md` Deliverable (occasionally per significant Task, for a large Deliverable). This is where architecture/code-quality observations, technical debt, and refactoring suggestions actually get recorded — not left in a closed Claude Code session's memory, not scattered across commit messages nobody re-reads. `CONTRIBUTING.md` §1 requires an entry here as part of finishing a Deliverable; `docs/DefinitionOfDone.md` §6 makes it part of the Definition of Done, not optional polish.

**Rules for this file:**
- **Append, don't edit history.** If a later Deliverable reveals an earlier observation was wrong, add a new entry noting that — don't go back and rewrite the old one. The log's value is in showing what was actually known/believed at each point, including when that turned out to be incomplete.
- **Newest entry last**, so reading top-to-bottom follows the project's actual timeline.
- **Every entry uses the template below, all five fields** — an entry that skips "Technical Debt" because "there wasn't any" should say that explicitly, not omit the heading.

## Template

```markdown
## YYYY-MM-DD — Deliverable DN — <short title>

**Architecture observations:** Did the actual implementation match what CLAUDE.md/ROADMAP.md described going in? Any boundary that was harder to hold than expected, or easier?

**Code quality observations:** Anything about the resulting code worth flagging — good or bad — that isn't already obvious from reading it (a pattern worth repeating elsewhere, a shortcut taken under time pressure, a test that turned out to be more valuable than expected).

**Technical debt:** Anything deliberately deferred, any known gap, any place a future Deliverable will need to revisit this one's work. Reference the specific file/type, not just a vague concern.

**Refactoring suggestions:** Concrete, not vague — "rule of three" candidates (CONTRIBUTING.md §3) that are now two-of-three and worth watching, not "this could probably be cleaner."

**Follow-ups filed:** Any `// TODO(DN.T)` comments added, any `docs/DECISIONS.md` entries this Deliverable produced.
```

---

## 2026-08-08 — Pre-Implementation Architecture Review (Batches 1–4)

Not a `ROADMAP.md` Deliverable in the normal sense — this entry documents the four-batch review-and-correction pass performed on `CLAUDE.md`/`SPEC.md`/`ROADMAP.md` *before* Deliverable D1 (or, at the time, "Milestone 1") began, seeded here so the log has real history from day one rather than starting empty at the first feature Deliverable.

**Architecture observations:** The original architecture documents (single initial commit) were internally consistent enough to look complete on a first read, but contained several real contradictions that would only have surfaced mid-implementation: `CLAUDE.md` told Views both to never touch `@Query`/SwiftData *and* to use `@Query` for list views, in two different sections; the tech-stack table claimed "compiler-enforced module boundaries" for a `Features/` folder that lived inside the app target, where nothing actually enforced that; `AsyncStream` and Foundation's `Progress` were referenced as if interchangeable despite having incompatible concurrency models. None of these would have been caught by "does it compile" — they're the kind of thing that only shows up once two different sessions, months apart, each read a different half of a contradiction and built against it.

**Code quality observations:** Two small pieces of real, tested code were built ahead of schedule specifically to de-risk locked-in architectural bets rather than leave them as unverified assumptions: `Packages/ACCore` (SMPTE drop-frame `Timecode` arithmetic, 18 tests including a 3-hour-equivalent round-trip sweep) and `Packages/ACExport` (a `libxlsxwriter` feasibility spike, verified under real kernel-enforced App Sandbox via an ad-hoc-signed `.app` bundle, not just source-code review). Both are minimal scaffolds, not the real feature work — see the `Package.swift` header comment in each for the explicit "don't mistake this for Deliverable completion" note.

**Technical debt:** `ROADMAP.md`'s pre-restructuring milestones (M13–M25, M31, in the old numbering) still referenced the pre-`ACFeatures`-package `Features/...` path instead of `Packages/ACFeatures/Sources/ACFeatures/...` at the time of this entry — a known, tracked gap, not silently carried forward. The CI workflow (`.github/workflows/ci.yml`) added in this same pass has an unverified assumption: the pinned Xcode version (`15.4`) for GitHub-hosted `macos-14` runners was written without access to a live runner to confirm against — flagged in the workflow file itself as something to confirm on first real run.

**Refactoring suggestions:** None yet — no feature code exists to refactor. The two spike packages (`ACCore`, `ACExport`) will need to be merged into the real Deliverable D1–D3 / D11 package structure rather than treated as separate, permanent scaffolds; that merge is Deliverable D1's job, not a follow-up refactor after the fact.

**Follow-ups filed:** `docs/DECISIONS.md` — full set of entries covering the `MediaDuration` rename, `ACFeatures` package split, drop-frame timecode, `libxlsxwriter` validation, progress/cancellation contract, waveform architecture, deployment target, Views/`@Query` resolution, module dependency graph, navigation model, and document/window model (including its single-window-then-multi-window reversal). See that file directly rather than duplicating its content here.

---

## 2026-08-08 — CI's first real run (not a Deliverable — a same-day follow-up to the entry above)

**Architecture observations:** The CI Xcode-pin risk flagged in the entry above as "unverified against a live runner" was real, not theoretical caution — the very first push after CI was added failed both `swift test` matrix jobs with an identical, unambiguous error (`Package.swift` declared `swift-tools-version: 6.1`, the pinned Xcode 15.4's Swift toolchain is 5.10). Diagnosed directly from `gh run view --log-failed`, not guessed at from symptoms.

**Code quality observations:** N/A — fix was a one-line manifest change in each `Package.swift` (`6.1` → `5.10`), not a code change.

**Technical debt:** None added. If anything, this closes debt: `swift-tools-version` in both packages now reflects an actually-considered floor (matching `CLAUDE.md`'s documented minimum Xcode) instead of whatever the authoring sandbox happened to have installed.

**Refactoring suggestions:** None.

**Follow-ups filed:** `docs/DECISIONS.md` gets a new entry for this fix. `SPEC.md` §6's "CI... hasn't been confirmed against a live runner" gap is updated to reflect that it has now been confirmed, and genuinely failed once before the fix.
