import Foundation

/// The shared progress/result shape for every long-running operation
/// (`AsyncThrowingStream<OperationProgress<T>, Error>`) — zero or more
/// `.progress` events followed by exactly one `.completed(T)` before the stream
/// finishes or throws. `T` is whatever the operation ultimately produces
/// (`AudioAsset` for import, `[Cue]` for detection, a file `URL` for export,
/// …). See CLAUDE.md's "Long-Running Operations: Progress & Cancellation"
/// section and SPEC.md §4.17.
public enum OperationProgress<Success: Sendable>: Sendable {
    case progress(ProgressUpdate)
    case completed(Success)
}
