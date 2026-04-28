import XCTest
@testable import Example_Point

final class ColorExtensionTests: XCTestCase {
    func testIrohaColorComponentsStayInRange() {
        assertColor(UIColor.iroha.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)),
                    equals: (red: 0.11, green: 0.34, blue: 0.61, alpha: 1.0))
        assertColor(UIColor.iroha.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)),
                    equals: (red: 228.0 / 255.0, green: 35.0 / 255.0, blue: 45.0 / 255.0, alpha: 1.0))
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

    private func assertColor(_ color: UIColor, equals expected: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        XCTAssertEqual(red, expected.red, accuracy: 0.001)
        XCTAssertEqual(green, expected.green, accuracy: 0.001)
        XCTAssertEqual(blue, expected.blue, accuracy: 0.001)
        XCTAssertEqual(alpha, expected.alpha, accuracy: 0.001)
    }
}
