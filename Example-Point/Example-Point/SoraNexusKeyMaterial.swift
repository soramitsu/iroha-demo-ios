import Foundation
import CryptoKit
import IrohaSwift

enum SoraKeyMaterialError: Error, LocalizedError {
    case unableToDeriveKeypair

    var errorDescription: String? {
        switch self {
        case .unableToDeriveKeypair:
            return "秘密鍵を導出できませんでした。"
        }
    }
}

struct SoraNexusKeyMaterial {
    let mnemonic: Mnemonic
    let wordCount: MnemonicWordCount
    let keypair: Keypair

    init(mnemonic: Mnemonic) throws {
        guard let count = MnemonicWordCount(count: mnemonic.words.count) else {
            throw MnemonicGeneratorError.invalidWordCount
        }
        self.mnemonic = mnemonic
        self.wordCount = count
        let privateKeyData = SoraNexusKeyMaterial.privateKeyBytes(from: mnemonic.entropy, count: count)
        self.keypair = try Keypair(privateKeyBytes: privateKeyData)
    }

    static func fromPhrase(_ phrase: String) throws -> SoraNexusKeyMaterial {
        let mnemonic = try MnemonicGenerator.shared.mnemonic(from: phrase)
        return try SoraNexusKeyMaterial(mnemonic: mnemonic)
    }

    var phrase: String {
        mnemonic.phrase
    }

    func accountId(using config: ToriiConfiguration) -> String {
        config.accountId(for: keypair.publicKey)
    }

    var privateKeyHex: String {
        keypair.privateKey.rawRepresentation.hexEncodedString()
    }

    var publicKeyHex: String {
        keypair.publicKey.hexEncodedString()
    }

    private static func privateKeyBytes(from entropy: Data, count: MnemonicWordCount) -> Data {
        switch count {
        case .twentyFour:
            return entropy
        case .twelve:
            return Data(SHA256.hash(data: entropy))
        }
    }
}
