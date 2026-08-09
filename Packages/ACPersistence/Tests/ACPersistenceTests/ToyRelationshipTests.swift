import SwiftData
import XCTest

/// THROWAWAY diagnostic — no relation to any real ACCore/ACPersistence type.
/// Tests whether a minimal to-many/to-one inverse `@Model` relationship
/// pair, structurally identical in shape to `ProjectEntity.cues` /
/// `CueEntity.project` (explicit `@Relationship(deleteRule:inverse:)` on the
/// to-many side, a bare un-annotated optional on the to-one/inverse side),
/// crashes the same way in complete isolation from every real entity in
/// this package. If this crashes too, the cause is systemic (Xcode 15.4's
/// SwiftData, this toolchain, or a real compiler bug) — not a mistake
/// specific to `ProjectEntity`/`CueEntity`. To be deleted once diagnosed.
@Model
final class ToyParent {
    var id: UUID
    @Relationship(deleteRule: .cascade, inverse: \ToyChild.parent) var children: [ToyChild]

    init(id: UUID) {
        self.id = id
        children = []
    }
}

@Model
final class ToyChild {
    var id: UUID
    var parent: ToyParent?

    init(id: UUID) {
        self.id = id
        parent = nil
    }
}

final class ToyRelationshipTests: XCTestCase {
    func test_toyParentChildRoundTrip() throws {
        let schema = Schema([ToyParent.self, ToyChild.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = ModelContext(container)

        let parent = ToyParent(id: UUID())
        let child = ToyChild(id: UUID())
        parent.children = [child]
        child.parent = parent

        context.insert(parent)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<ToyParent>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.children.count, 1)
    }
}
