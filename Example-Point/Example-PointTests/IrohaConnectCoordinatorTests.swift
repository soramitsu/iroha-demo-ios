import Foundation
import XCTest
@testable import Example_Point

final class IrohaConnectCoordinatorTests: XCTestCase {
    func testPayloadParsing() throws {
        let accountId = testAccountId(seed: 77)
        let urlString = "example-point://irohaconnect?accountId=\(accountId)&accountAlias=treasury%40banking.retail&publicKey=abcdef&privateKey=123456&displayName=Sora"
        guard let url = URL(string: urlString) else {
            XCTFail("Unable to create URL")
            return
        }
        let payload = try IrohaConnectPayload(url: url)
        XCTAssertEqual(payload.accountId, accountId)
        XCTAssertEqual(payload.accountAlias, "treasury@banking.retail")
        XCTAssertEqual(payload.publicKeyHex, "abcdef")
        XCTAssertEqual(payload.privateKeyHex, "123456")
        XCTAssertEqual(payload.displayName, "Sora")
    }

    func testPayloadMissingFieldThrows() {
        let accountId = testAccountId(seed: 78)
        let urlString = "example-point://irohaconnect?accountId=\(accountId)&publicKey=abc"
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
