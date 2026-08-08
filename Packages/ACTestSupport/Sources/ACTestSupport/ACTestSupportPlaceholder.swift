import Foundation

/// Scaffolding proving this package builds and links inside AutoCue.xcworkspace
/// — not real feature code. Superseded starting at ROADMAP.md D3 (in-memory
/// fake Repository implementations). Never linked into a `.target`, including
/// the App target — only into `.testTarget`s (CLAUDE.md, Naming Conventions).
public enum ACTestSupportPlaceholder {
    public static let isScaffolded = true
}
