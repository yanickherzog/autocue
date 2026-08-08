import Foundation

/// Placeholder for ROADMAP.md D1. The real wiring — one factory method per
/// top-level Feature ViewModel, backed by concrete Repository implementations —
/// is built at D6/T6.1 per CLAUDE.md's "Dependency Injection Pattern." This is
/// the only type in the codebase ever allowed to construct a concrete
/// Repository or Use Case; nothing else does, even once it's real.
final class DependencyContainer {}
