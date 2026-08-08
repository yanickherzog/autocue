import SwiftUI

/// Thin composition root. Scaffolding for ROADMAP.md D1 — the real multi-scene
/// shell (Library scene, `WindowGroup(for: Project.ID.self)`, `Settings` scene,
/// `OpenProjectWindowRegistry`) is built at D6/T6.1 per CLAUDE.md's "Document &
/// Window Model."
@main
struct AutoCueApp: App {
    var body: some Scene {
        WindowGroup {
            Text("AutoCue")
        }
    }
}
