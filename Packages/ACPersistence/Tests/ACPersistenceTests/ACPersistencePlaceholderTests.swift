@testable import ACPersistence
import XCTest

final class ACPersistencePlaceholderTests: XCTestCase {
    func test_packageBuildsAndLinks() {
        XCTAssertTrue(ACPersistencePlaceholder.isScaffolded)
    }
}
