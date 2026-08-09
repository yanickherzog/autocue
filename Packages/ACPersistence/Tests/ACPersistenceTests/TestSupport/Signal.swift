import Foundation

/// A one-shot async gate for deterministically sequencing concurrency tests
/// without wall-clock `sleep` assumptions (`CONTRIBUTING.md`'s flaky-test
/// warning applies just as much to a repository concurrency test as to a UI
/// test). `wait()` suspends until `fire()` is called; `fire()` before
/// `wait()` is also safe (`wait()` returns immediately in that case).
actor Signal {
    private var isFired = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func fire() {
        guard !isFired else { return }
        isFired = true
        for continuation in continuations {
            continuation.resume()
        }
        continuations = []
    }

    func wait() async {
        if isFired {
            return
        }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }
}
