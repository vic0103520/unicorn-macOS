import XCTest
@testable import UnicornCore

// XCTest is intentionally isolated to this legacy operator parity case. Current Swift SDKs declare
// >>= with a conflicting precedence across module boundaries, so the Optional implementation is
// exercised through the named function that the preserved operator delegates to.
final class LegacyFunctionalOperatorTests: XCTestCase {
    func testFunctionalOperatorsPipeValuesAndBindOptionals() {
        let result = 5 |> { $0 * 2 } |> { $0 + 3 }
        XCTAssertEqual(result, 13)

        let optional: Int? = 5
        let bound = bindOptional(optional, using: { $0 > 0 ? $0 * 2 : nil })
        XCTAssertEqual(bound, 10)

        let nilOptional: Int? = nil
        let failedBound = bindOptional(nilOptional, using: { $0 * 2 })
        XCTAssertNil(failedBound)
    }
}
