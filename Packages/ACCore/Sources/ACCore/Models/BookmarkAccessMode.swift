import Foundation

/// Whether a stored security-scoped bookmark is a real security-scoped
/// bookmark (the normal case) or a plain, non-security-scoped fallback
/// captured because security-scoped `bookmarkData(options: .withSecurityScope,
/// ...)` creation itself failed for this file — a real, documented macOS
/// failure mode independent of this app's own logic, not something the
/// importing Use Case can avoid or retry its way out of. See "Security-scoped
/// bookmark creation can fail entirely," SPEC.md §4.10, and
/// `docs/DECISIONS.md`.
///
/// A `.plainFallback` bookmark is genuinely usable for the remainder of the
/// *current* app session (the sandbox extension granted at import time is
/// still active), but — unlike `.securityScoped` — is not guaranteed to still
/// grant access after the app relaunches.
///
/// **Promoted from `AudioAsset.BookmarkAccessMode` (`ROADMAP.md` D12)** — a
/// second real caller, `WAFormTemplateReference`, now needs the exact same
/// bookmark-lifecycle concept for the user's imported WA Film template PDF,
/// not just an imported WAV file. `CLAUDE.md` rule 7's promotion bar (a real
/// second caller, not a hypothetical one) is met; nesting it under
/// `AudioAsset` specifically no longer describes what it actually is. See
/// `docs/DECISIONS.md` for the full record.
///
/// Conformances: `Equatable`, `Sendable` (`CLAUDE.md`, "Domain Model
/// Value-Type Conformances" — no `id` field, not `Identifiable`, same shape
/// as `TimecodeFrameRate`). `RawRepresentable` (`String`) purely so
/// `ACPersistence`/a `UserDefaults`-backed store can persist it as a plain
/// string column without a separate mapping enum of its own.
public enum BookmarkAccessMode: String, Equatable, Sendable {
    case securityScoped
    case plainFallback
}
