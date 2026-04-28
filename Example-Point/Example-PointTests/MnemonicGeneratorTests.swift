import Foundation
import XCTest
@testable import Example_Point

final class MnemonicGeneratorTests: XCTestCase {
    func testWordMatrixContainsExpectedEntries() {
        XCTAssertEqual(MnemonicGenerator.shared.availableWordCount, 2048)
    }

    func testRoundTripMnemonicFromEntropy() throws {
        let bytes = (0..<16).map { UInt8($0) }
        let entropy = Data(bytes)
        let generator = MnemonicGenerator.shared
        let mnemonic = try generator.mnemonic(from: entropy)
        XCTAssertEqual(mnemonic.words.count, 12)
        let reconstructed = try generator.mnemonic(from: mnemonic.phrase)
        XCTAssertEqual(reconstructed.words, mnemonic.words)
        XCTAssertEqual(reconstructed.entropy, mnemonic.entropy)
    }

    func testSoraKeyMaterialUsesDeterministicPrivateKeyForTwelveWords() throws {
        let bytes = (0..<16).map { _ in UInt8.random(in: 0...255) }
        let entropy = Data(bytes)
        let generator = MnemonicGenerator.shared
        let mnemonic = try generator.mnemonic(from: entropy)
        let material = try SoraNexusKeyMaterial(mnemonic: mnemonic)
        XCTAssertEqual(material.wordCount, .twelve)
        XCTAssertEqual(material.keypair.privateKey.rawRepresentation.count, 32)
    }

    func testTwentyFourWordMnemonicProvidesFullEntropy() throws {
        let bytes = (0..<32).map { UInt8($0 & 0xFF) }
        let entropy = Data(bytes)
        let generator = MnemonicGenerator.shared
        let mnemonic = try generator.mnemonic(from: entropy)
        XCTAssertEqual(mnemonic.words.count, 24)
        let material = try SoraNexusKeyMaterial(mnemonic: mnemonic)
        XCTAssertEqual(material.wordCount, .twentyFour)
        XCTAssertEqual(material.keypair.privateKey.rawRepresentation, mnemonic.entropy)
    }
}
