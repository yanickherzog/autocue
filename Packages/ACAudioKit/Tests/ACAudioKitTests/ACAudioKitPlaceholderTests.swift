@testable import ACAudioKit
import XCTest

final class ACAudioKitPlaceholderTests: XCTestCase {
    func test_packageBuildsAndLinks() {
        XCTAssertTrue(ACAudioKitPlaceholder.isScaffolded)
    }
}
