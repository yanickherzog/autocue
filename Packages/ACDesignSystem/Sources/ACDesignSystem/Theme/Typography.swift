import CoreText
import SwiftUI

public extension Theme {
    /// Weight for `Theme.Typography.font(_:size:)`. A sibling of `Typography`, not
    /// nested inside it, to keep type nesting at most 1 level deep (SwiftLint's
    /// `nesting` rule).
    enum FontWeight {
        case regular
        case medium
        case bold

        var postScriptName: String {
            switch self {
            case .regular: "SpaceGrotesk-Regular"
            case .medium: "SpaceGrotesk-Medium"
            case .bold: "SpaceGrotesk-Bold"
            }
        }
    }

    /// Space Grotesk (Google Fonts, SIL Open Font License), bundled as static
    /// weights under `Resources/Fonts/`. No Light weight is bundled — ghost text's
    /// de-emphasis is carried entirely by `Theme.Colors.ghostTextPrimary`'s opacity,
    /// not by font weight. See CLAUDE.md, "Visual Language."
    enum Typography {
        /// A Space Grotesk font at the given weight and size.
        ///
        /// Registration happens lazily and idempotently on first use — no caller
        /// needs to remember to call `registerFonts()` first.
        public static func font(_ weight: FontWeight, size: CGFloat) -> Font {
            _ = registrationTrigger
            return Font.custom(weight.postScriptName, size: size)
        }

        /// Registers every bundled Space Grotesk weight with Core Text for the
        /// current process. Safe to call more than once — subsequent calls are a
        /// no-op. Exposed publicly only for the rare case an early, explicit call
        /// (e.g. to front-load registration before first paint) is wanted; `font(_:size:)`
        /// already triggers this automatically.
        public static func registerFonts() {
            _ = registrationTrigger
        }

        /// `static let` initializers are lazy and thread-safe, which is exactly the
        /// "register once, on first use, from any thread" behavior this needs.
        private static let registrationTrigger: Void = {
            let weights: [FontWeight] = [.regular, .medium, .bold]
            for weight in weights {
                guard let url = Bundle.module.url(
                    forResource: weight.postScriptName,
                    withExtension: "ttf",
                    subdirectory: "Fonts"
                ) else {
                    continue
                }
                var error: Unmanaged<CFError>?
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            }
        }()
    }
}
