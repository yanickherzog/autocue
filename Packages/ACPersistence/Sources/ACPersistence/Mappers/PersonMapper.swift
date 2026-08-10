import ACCore
import Foundation

/// Converts `ACCore.Person` to/from `PersonEntity`.
enum PersonMapper {
    static func toEntity(_ person: Person, order: Int) -> PersonEntity {
        PersonEntity(
            id: person.id,
            order: order,
            firstName: person.firstName,
            lastName: person.lastName,
            ipiNumber: person.ipiNumber,
            addressStreet: person.address?.street,
            addressPostalCode: person.address?.postalCode,
            addressCity: person.address?.city,
            addressCountry: person.address?.country,
            email: person.email,
            swissPerformNumber: person.swissPerformNumber,
            intendedRoleRawValue: person.intendedRole.map(rawValue(for:))
        )
    }

    static func toDomain(_ entity: PersonEntity) throws -> Person {
        try Person(
            id: entity.id,
            firstName: entity.firstName,
            lastName: entity.lastName,
            ipiNumber: entity.ipiNumber,
            address: address(
                street: entity.addressStreet,
                postalCode: entity.addressPostalCode,
                city: entity.addressCity,
                country: entity.addressCountry
            ),
            email: entity.email,
            swissPerformNumber: entity.swissPerformNumber,
            intendedRole: entity.intendedRoleRawValue.map(intendedRole(from:))
        )
    }

    private static func rawValue(for value: PersonIntendedRole) -> String {
        switch value {
        case .composer: "composer"
        case .arranger: "arranger"
        case .performer: "performer"
        }
    }

    private static func intendedRole(from rawValue: String) throws -> PersonIntendedRole {
        switch rawValue {
        case "composer": .composer
        case "arranger": .arranger
        case "performer": .performer
        default: throw MappingError.unknownRawValue(type: "PersonIntendedRole", rawValue: rawValue)
        }
    }

    /// `PostalAddress` is all-or-nothing at the domain level — reconstructed
    /// only if every part is present; any partial state (which a hand-edited
    /// store, not a normal round-trip, could in principle produce) is treated
    /// as "no address" rather than a partially-filled `PostalAddress`, since
    /// the domain type has no way to represent a partial address at all.
    private static func address(
        street: String?,
        postalCode: String?,
        city: String?,
        country: String?
    ) -> PostalAddress? {
        guard let street, let postalCode, let city, let country else {
            return nil
        }
        return PostalAddress(street: street, postalCode: postalCode, city: city, country: country)
    }
}
