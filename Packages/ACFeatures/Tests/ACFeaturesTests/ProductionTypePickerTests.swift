import ACCore
@testable import ACFeatures
import XCTest

/// Direct coverage for `ProductionTypePicker.displayNames` — the lookup
/// table exists specifically to stay under SwiftLint's cyclomatic-complexity
/// threshold (`ProductionTypePicker`'s own doc comment), which means it
/// isn't compiler-checked for exhaustiveness the way a `switch` over the
/// enum would be. Same pattern `SetupMapperTests` already establishes for
/// `SetupMapper`'s equivalent `ProductionType` table.
final class ProductionTypePickerTests: XCTestCase {
    func test_everyProductionTypeCaseHasADisplayName() {
        for type in ProductionType.allCases {
            XCTAssertFalse(ProductionTypePicker.displayName(type).isEmpty)
        }
    }
}
