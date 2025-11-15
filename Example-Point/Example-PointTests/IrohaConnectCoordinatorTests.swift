import Foundation
import XCTest
@testable import Example_Point

final class IrohaConnectCoordinatorTests: XCTestCase {
    func testPayloadParsing() throws {
        let urlString = "example-point://irohaconnect?accountId=user%40domain&publicKey=abcdef&privateKey=123456&displayName=Sora"
        guard let url = URL(string: urlString) else {
            XCTFail("Unable to create URL")
            return
        }
        let payload = try IrohaConnectPayload(url: url)
        XCTAssertEqual(payload.accountId, "user@domain")
        XCTAssertEqual(payload.publicKeyHex, "abcdef")
        XCTAssertEqual(payload.privateKeyHex, "123456")
        XCTAssertEqual(payload.displayName, "Sora")
    }

    func testPayloadMissingFieldThrows() {
        let urlString = "example-point://irohaconnect?accountId=user%40domain&publicKey=abc"
        guard let url = URL(string: urlString) else {
            XCTFail("Unable to create URL")
            return
        }
        XCTAssertThrowsError(try IrohaConnectPayload(url: url)) { error in
            guard case IrohaConnectError.missingField(let field) = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
            XCTAssertEqual(field, "privateKey")
        }
    }
}
