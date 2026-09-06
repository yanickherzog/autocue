/// Test-only: lets a `writeHook` pause exactly the *first* write it's
/// invoked for and pass every subsequent one straight through, without
/// capturing a plain mutable `var` in the `@Sendable` hook closure (which
/// would either fail to compile or be a genuine data race under strict
/// concurrency checking). Shared across test files (`ProjectRepositoryImplTests`,
/// `ReaderWriterBarrierTests`) rather than duplicated per file.
actor PauseOnceGate {
    private var hasPausedOnce = false

    func shouldPauseOnce() -> Bool {
        guard !hasPausedOnce else { return false }
        hasPausedOnce = true
        return true
    }
}
