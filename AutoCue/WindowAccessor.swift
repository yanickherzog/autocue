import AppKit
import SwiftUI

/// Captures the hosting `NSWindow` for the SwiftUI view it's attached to, so
/// `ProjectWindowView` can register/unregister itself with
/// `OpenProjectWindowRegistry` on appear/disappear. The AppKit-interop escape
/// hatch `CLAUDE.md`'s Technology Stack table allows for "when SwiftUI has a
/// genuine gap" — SwiftUI has no direct API to obtain a view's own `NSWindow`.
struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onResolve(window)
            }
        }
        return view
    }

    func updateNSView(_: NSView, context _: Context) {}
}
