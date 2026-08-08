@testable import ACTestSupport
import XCTest

final class ACTestSupportPlaceholderTests: XCTestCase {
    func test_packageBuildsAndLinks() {
        XCTAssertTrue(ACTestSupportPlaceholder.isScaffolded)
    }
}
