import XCTest
@testable import Example_Point

final class ColorExtensionTests: XCTestCase {
    func testIrohaColorComponentsStayInRange() {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        XCTAssertTrue(UIColor.iroha.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        XCTAssertEqual(red, 228.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(green, 35.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(blue, 45.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(alpha, 1.0, accuracy: 0.001)
    }

    func testHexHelperParsesSixDigitColors() {
        let color = UIColor.hex(hex: "E4232D", alpha: 0.5)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        XCTAssertEqual(red, 228.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(green, 35.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(blue, 45.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(alpha, 0.5, accuracy: 0.001)
    }
}
