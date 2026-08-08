@testable import ACFeatures
import XCTest

final class ACFeaturesPlaceholderTests: XCTestCase {
    func test_packageBuildsAndLinks() {
        XCTAssertTrue(ACFeaturesPlaceholder.isScaffolded)
    }
}
