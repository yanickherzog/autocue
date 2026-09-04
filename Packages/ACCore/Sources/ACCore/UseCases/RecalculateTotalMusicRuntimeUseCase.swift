import Foundation

/// The single, reusable sum `Setup.totalMusicRuntime`'s update rule is built
/// on (SPEC.md §4.14) — a plain, pure static helper, not a stateful type,
/// since it has no Repository dependency and nothing to orchestrate (same
/// shape as `PartyResolver`). Called from every site that mutates
/// `Project.cues` and needs to keep `Setup.totalMusicRuntime` in sync
/// (`UpdateCueUseCase`, `ROADMAP.md` D9/D10), so the sum is computed
/// identically everywhere, never copied.
public enum RecalculateTotalMusicRuntimeUseCase {
    public static func recalculate(cues: [Cue]) -> MediaDuration {
        cues.reduce(.zero) { $0 + $1.duration }
    }
}
