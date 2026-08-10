import ACCore
import CoreGraphics
import Foundation

/// Explicit, per-`Project.ID` window-frame persistence (`ROADMAP.md` D6,
/// manual verification follow-up).
///
/// **Replaces an earlier attempt using `NSWindow.setFrameAutosaveName`,
/// which was tested empirically and found not to work.** `defaults read
/// com.autocue.AutoCue` after a real resize/quit cycle showed no
/// `"NSWindow Frame ProjectWindow-<uuid>"` key at all — the call never
/// actually persisted anything. What *was* present: SwiftUI's own
/// `WindowGroup(for:)` already runs its own internal frame-restoration
/// system, keyed by an auto-generated name based on the scene's content
/// type plus a window-open ordinal (e.g. `"NSWindow Frame
/// SwiftUI.PresentedWindowContent<Foundation.UUID,
/// Swift.Optional<AutoCue.ProjectWindowView>>-2-AppWindow-1"`), not by
/// `Project.ID`. That's a plausible reason `setFrameAutosaveName` never
/// engaged — SwiftUI already owns frame restoration for this window kind —
/// but more importantly, the *symptom* it produces is exactly the one
/// observed: reopening the same `Project` doesn't reliably map back to the
/// same ordinal-keyed entry, so the saved frame isn't applied. This store
/// sidesteps SwiftUI's restoration entirely and does the job explicitly,
/// keyed by `Project.ID` specifically.
///
/// Stored as a plain, human-readable `"x,y,width,height"` string (not
/// `NSStringFromRect`/a binary blob) specifically so it's directly
/// inspectable via `defaults read com.autocue.AutoCue | grep
/// ProjectWindowFrame` without needing to decode anything — the same
/// verification method that caught the `setFrameAutosaveName` failure in
/// the first place.
enum ProjectWindowFrameStore {
    private static func key(for projectID: Project.ID) -> String {
        "ProjectWindowFrame-\(projectID.uuidString)"
    }

    static func savedFrame(for projectID: Project.ID, defaults: UserDefaults = .standard) -> CGRect? {
        guard let raw = defaults.string(forKey: key(for: projectID)) else { return nil }
        let parts = raw.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 4 else { return nil }
        return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }

    static func save(_ frame: CGRect, for projectID: Project.ID, defaults: UserDefaults = .standard) {
        let raw = "\(frame.origin.x),\(frame.origin.y),\(frame.size.width),\(frame.size.height)"
        defaults.set(raw, forKey: key(for: projectID))
    }
}
