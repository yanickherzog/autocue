import Foundation

/// One incremental status update from a long-running operation. See
/// `OperationProgress` and CLAUDE.md's "Long-Running Operations: Progress &
/// Cancellation" section — this is the shared shape every such operation reports
/// through, never Foundation's `Progress` (SPEC.md §4.17).
public struct ProgressUpdate: Sendable, Equatable {
    public let fractionCompleted: Double
    public let message: String?

    public init(fractionCompleted: Double, message: String? = nil) {
        self.fractionCompleted = fractionCompleted
        self.message = message
    }
}
