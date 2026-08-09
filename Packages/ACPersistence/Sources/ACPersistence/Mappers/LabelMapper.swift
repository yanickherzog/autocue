import ACCore
import Foundation

/// Converts `ACCore.Label` to/from `LabelEntity`.
enum LabelMapper {
    static func toEntity(_ label: Label, order: Int) -> LabelEntity {
        LabelEntity(
            id: label.id,
            order: order,
            name: label.name,
            addressStreet: label.address.street,
            addressPostalCode: label.address.postalCode,
            addressCity: label.address.city,
            addressCountry: label.address.country,
            ipiNumber: label.ipiNumber,
            kind: label.kind.map(rawValue(for:))
        )
    }

    static func toDomain(_ entity: LabelEntity) throws -> Label {
        try Label(
            id: entity.id,
            name: entity.name,
            address: PostalAddress(
                street: entity.addressStreet,
                postalCode: entity.addressPostalCode,
                city: entity.addressCity,
                country: entity.addressCountry
            ),
            ipiNumber: entity.ipiNumber,
            kind: entity.kind.map(labelKind(from:))
        )
    }

    private static func rawValue(for value: LabelKind) -> String {
        switch value {
        case .publisher: "publisher"
        case .productionCompany: "productionCompany"
        case .broadcaster: "broadcaster"
        case .other: "other"
        }
    }

    private static func labelKind(from rawValue: String) throws -> LabelKind {
        switch rawValue {
        case "publisher": .publisher
        case "productionCompany": .productionCompany
        case "broadcaster": .broadcaster
        case "other": .other
        default: throw MappingError.unknownRawValue(type: "LabelKind", rawValue: rawValue)
        }
    }
}
