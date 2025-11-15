import XCTest
@testable import Example_Point

final class GlassmorphicStyleTests: XCTestCase {
    func testGradientBackgroundViewIgnoresHitTesting() {
        let background = GradientBackgroundView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))

        XCTAssertFalse(background.isUserInteractionEnabled)
        XCTAssertFalse(background.point(inside: CGPoint(x: 100, y: 100), with: nil))
    }

    func testBlurOverlayInsertedByGlassCardIsNonInteractive() {
        let card = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        card.applyGlassCardStyle()

        guard let blur = card.subviews.first(where: { $0 is UIVisualEffectView }) else {
            return XCTFail("Expected UIVisualEffectView blur to be inserted")
        }

        XCTAssertFalse(blur.isUserInteractionEnabled)
        XCTAssertFalse(blur.point(inside: CGPoint(x: 10, y: 10), with: nil))
    }
}
