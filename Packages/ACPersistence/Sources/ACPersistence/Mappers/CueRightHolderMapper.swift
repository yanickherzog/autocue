import ACCore
import Foundation

/// Converts `ACCore.CueRightHolder` to/from `CueRightHolderEntity`.
enum CueRightHolderMapper {
    static func toEntity(_ rightHolder: CueRightHolder, order: Int) -> CueRightHolderEntity {
        CueRightHolderEntity(
            order: order,
            partyKind: PartyMapper.kind(for: rightHolder.party),
            partyID: PartyMapper.id(for: rightHolder.party),
            role: rawValue(for: rightHolder.role),
            performanceBroadcastShare: rightHolder.performanceBroadcastShare,
            mechanicalRightsShare: rightHolder.mechanicalRightsShare,
            publishingContractAttached: rightHolder.publishingContractAttached,
            arrangementAuthorizationAttached: rightHolder.arrangementAuthorizationAttached
        )
    }

    static func toDomain(_ entity: CueRightHolderEntity) throws -> CueRightHolder {
        try CueRightHolder(
            party: PartyMapper.party(kind: entity.partyKind, id: entity.partyID),
            role: role(from: entity.role),
            performanceBroadcastShare: entity.performanceBroadcastShare,
            mechanicalRightsShare: entity.mechanicalRightsShare,
            publishingContractAttached: entity.publishingContractAttached,
            arrangementAuthorizationAttached: entity.arrangementAuthorizationAttached
        )
    }

    private static func rawValue(for value: CueRightHolderRole) -> String {
        switch value {
        case .composer: "composer"
        case .author: "author"
        case .arranger: "arranger"
        case .publisher: "publisher"
        case .performer: "performer"
        }
    }

    private static func role(from rawValue: String) throws -> CueRightHolderRole {
        switch rawValue {
        case "composer": .composer
        case "author": .author
        case "arranger": .arranger
        case "publisher": .publisher
        case "performer": .performer
        default: throw MappingError.unknownRawValue(type: "CueRightHolderRole", rawValue: rawValue)
        }
    }
}
