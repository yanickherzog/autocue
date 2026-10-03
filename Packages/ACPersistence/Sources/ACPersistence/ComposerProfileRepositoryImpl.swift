import ACCore
import Foundation

/// The real `ComposerProfileRepository` implementation.
///
/// **`UserDefaults`-backed, not `SwiftData`** — same reasoning as
/// `WAFormTemplateRepositoryImpl` (`ACExport`): one small, app-level value,
/// not a growing per-`Project` collection, so the full `SwiftData` schema/
/// mapper machinery would be disproportionate. Individual fields are stored
/// under their own keys rather than one `Codable`-encoded blob — avoids
/// adding `Codable` conformance to `ComposerProfile` for a single call site
/// (`CLAUDE.md` rule 16), and mirrors `WAFormTemplateRepositoryImpl.store`'s
/// own per-field pattern exactly.
public struct ComposerProfileRepositoryImpl: ComposerProfileRepository, @unchecked Sendable {
    private enum Key {
        static let firstName = "ComposerProfile.firstName"
        static let lastName = "ComposerProfile.lastName"
        static let ipiNumber = "ComposerProfile.ipiNumber"
        static let email = "ComposerProfile.email"
        static let swissPerformNumber = "ComposerProfile.swissPerformNumber"
        static let street = "ComposerProfile.address.street"
        static let postalCode = "ComposerProfile.address.postalCode"
        static let city = "ComposerProfile.address.city"
        static let country = "ComposerProfile.address.country"
        /// Distinguishes "never saved" from "saved with every optional field
        /// empty" — without this, `currentProfile()` couldn't tell the two
        /// apart purely from `firstName`/`lastName`/`ipiNumber` being absent,
        /// since an empty `UserDefaults` string read returns `nil` either way.
        static let hasSavedProfile = "ComposerProfile.hasSavedProfile"
    }

    /// `UserDefaults` is documented by Apple as safe for concurrent access
    /// from any thread — see `WAFormTemplateRepositoryImpl`'s identical note
    /// for why that makes `@unchecked Sendable` correct here too.
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func currentProfile() -> ComposerProfile? {
        guard
            defaults.bool(forKey: Key.hasSavedProfile),
            let firstName = defaults.string(forKey: Key.firstName),
            let lastName = defaults.string(forKey: Key.lastName),
            let ipiNumber = defaults.string(forKey: Key.ipiNumber)
        else { return nil }

        let address: PostalAddress? = {
            guard
                let street = defaults.string(forKey: Key.street),
                let postalCode = defaults.string(forKey: Key.postalCode),
                let city = defaults.string(forKey: Key.city),
                let country = defaults.string(forKey: Key.country)
            else { return nil }
            return PostalAddress(street: street, postalCode: postalCode, city: city, country: country)
        }()

        return ComposerProfile(
            firstName: firstName,
            lastName: lastName,
            ipiNumber: ipiNumber,
            address: address,
            email: defaults.string(forKey: Key.email),
            swissPerformNumber: defaults.string(forKey: Key.swissPerformNumber)
        )
    }

    public func saveProfile(_ profile: ComposerProfile) throws {
        defaults.set(profile.firstName, forKey: Key.firstName)
        defaults.set(profile.lastName, forKey: Key.lastName)
        defaults.set(profile.ipiNumber, forKey: Key.ipiNumber)
        defaults.set(profile.email, forKey: Key.email)
        defaults.set(profile.swissPerformNumber, forKey: Key.swissPerformNumber)
        defaults.set(profile.address?.street, forKey: Key.street)
        defaults.set(profile.address?.postalCode, forKey: Key.postalCode)
        defaults.set(profile.address?.city, forKey: Key.city)
        defaults.set(profile.address?.country, forKey: Key.country)
        defaults.set(true, forKey: Key.hasSavedProfile)
    }
}
