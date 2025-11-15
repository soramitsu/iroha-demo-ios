import Foundation
import CryptoKit
import Security

enum MnemonicGeneratorError: Error, LocalizedError {
    case invalidEntropyLength
    case invalidWordCount
    case wordNotFound(String)
    case checksumMismatch
    case randomGenerationFailed

    var errorDescription: String? {
        switch self {
        case .invalidEntropyLength:
            return "Entropy must be 128 or 256 bits."
        case .invalidWordCount:
            return "The mnemonic must contain either 12 or 24 words."
        case .wordNotFound(let word):
            return "\(word) はサポートされていない単語です。"
        case .checksumMismatch:
            return "単語リストのチェックサムが一致しません。"
        case .randomGenerationFailed:
            return "安全な乱数を生成できませんでした。"
        }
    }
}

enum MnemonicWordCount: Int, CaseIterable {
    case twelve = 12
    case twentyFour = 24

    var entropyLength: Int {
        switch self {
        case .twelve:
            return 16
        case .twentyFour:
            return 32
        }
    }

    init?(count: Int) {
        switch count {
        case 12:
            self = .twelve
        case 24:
            self = .twentyFour
        default:
            return nil
        }
    }
}

struct Mnemonic: Equatable {
    let words: [String]
    let entropy: Data

    var phrase: String {
        words.joined(separator: " ")
    }
}

final class MnemonicGenerator {
    static let shared = MnemonicGenerator()

    private let wordList: [String]
    private let wordLookup: [String: Int]

    private init() {
        self.wordList = Self.makeWordList()
        self.wordLookup = Dictionary(uniqueKeysWithValues: wordList.enumerated().map { ($0.element, $0.offset) })
    }

    var availableWordCount: Int {
        wordList.count
    }

    func generate(wordCount: MnemonicWordCount) throws -> Mnemonic {
        let entropy = try generateEntropy(byteCount: wordCount.entropyLength)
        return try mnemonic(from: entropy)
    }

    func mnemonic(from phrase: String) throws -> Mnemonic {
        let parts = phrase
            .split(separator: " ")
            .map { String($0).lowercased() }
        return try mnemonic(from: parts)
    }

    func mnemonic(from words: [String]) throws -> Mnemonic {
        guard let wordCount = MnemonicWordCount(count: words.count) else {
            throw MnemonicGeneratorError.invalidWordCount
        }
        let normalized = words.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let entropy = try entropyData(from: normalized, wordCount: wordCount)
        return Mnemonic(words: normalized, entropy: entropy)
    }

    func mnemonic(from entropy: Data) throws -> Mnemonic {
        guard MnemonicWordCount(count: entropy.count * 3 / 4) != nil else {
            throw MnemonicGeneratorError.invalidEntropyLength
        }
        let checksumBits = entropy.count * 8 / 32
        let entropyBits = bits(from: entropy)
        let hashBits = bits(from: Data(SHA256.hash(data: entropy)))
        let checksumEnd = hashBits.index(hashBits.startIndex, offsetBy: checksumBits)
        let checksum = Array(hashBits[hashBits.startIndex..<checksumEnd])
        let combined = entropyBits + checksum
        var words: [String] = []
        for chunk in stride(from: 0, to: combined.count, by: 11) {
            let slice = combined[chunk..<chunk + 11]
            let index = bitsToInt(Array(slice))
            words.append(wordList[index])
        }
        return Mnemonic(words: words, entropy: entropy)
    }

    private func entropyData(from words: [String], wordCount: MnemonicWordCount) throws -> Data {
        var bitStream: [Bool] = []
        for word in words {
            guard let index = wordLookup[word] else {
                throw MnemonicGeneratorError.wordNotFound(word)
            }
            let chunk = intToBits(index, bitsCount: 11)
            bitStream.append(contentsOf: chunk)
        }
        let entropyBitCount = wordCount.entropyLength * 8
        let checksumBitCount = entropyBitCount / 32
        let entropyBits = Array(bitStream.prefix(entropyBitCount))
        let checksumBits = Array(bitStream.suffix(checksumBitCount))
        let entropy = data(from: entropyBits)
        let hashBits = bits(from: Data(SHA256.hash(data: entropy)))
        let checksumEnd = hashBits.index(hashBits.startIndex, offsetBy: checksumBitCount)
        let calculatedChecksum = Array(hashBits[hashBits.startIndex..<checksumEnd])
        guard checksumBits == calculatedChecksum else {
            throw MnemonicGeneratorError.checksumMismatch
        }
        return entropy
    }

    private func generateEntropy(byteCount: Int) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &buffer)
        guard status == errSecSuccess else {
            throw MnemonicGeneratorError.randomGenerationFailed
        }
        return Data(buffer)
    }

    private func bits(from data: Data) -> [Bool] {
        var result: [Bool] = []
        for byte in data {
            for shift in stride(from: 7, through: 0, by: -1) {
                let bit = ((byte >> shift) & 0x01) == 1
                result.append(bit)
            }
        }
        return result
    }

    private func data(from bits: [Bool]) -> Data {
        var data = Data()
        for groupStart in stride(from: 0, to: bits.count, by: 8) {
            var byte: UInt8 = 0
            for bitIndex in 0..<8 {
                let targetIndex = groupStart + bitIndex
                guard targetIndex < bits.count else { continue }
                byte <<= 1
                byte |= bits[targetIndex] ? 1 : 0
            }
            data.append(byte)
        }
        return data
    }

    private func bitsToInt(_ bits: [Bool]) -> Int {
        var value = 0
        for bit in bits {
            value <<= 1
            value |= bit ? 1 : 0
        }
        return value
    }

    private func intToBits(_ value: Int, bitsCount: Int) -> [Bool] {
        var bits = [Bool](repeating: false, count: bitsCount)
        for index in 0..<bitsCount {
            let shift = bitsCount - 1 - index
            bits[index] = ((value >> shift) & 1) == 1
        }
        return bits
    }

    private static func makeWordList() -> [String] {
        let prefixes = [
            "aero", "amber", "apex", "aqua", "astro", "aurora", "binary", "blaze",
            "cinder", "cobalt", "cosmo", "crimson", "crypto", "delta", "ember", "ferrum",
            "glimmer", "halo", "hyper", "ionic", "lunar", "matrix", "nebula", "nova",
            "onyx", "oracle", "photon", "quantum", "radiant", "sol", "terra", "zenith"
        ]
        let suffixes = [
            "ace", "aether", "arc", "ash", "atom", "aurum", "axis", "beacon",
            "bloom", "bolt", "bond", "brink", "burst", "calm", "crest", "crown",
            "current", "dawn", "delta", "drift", "echo", "ember", "flux", "forge",
            "gale", "gleam", "glow", "glyph", "grid", "grove", "guard", "halo",
            "harbor", "haven", "haze", "horizon", "ion", "keeper", "knot", "lace",
            "lake", "lane", "lattice", "league", "light", "loom", "mark", "mesh",
            "moss", "nova", "orbit", "path", "peak", "pulse", "quill", "ridge",
            "rise", "river", "shard", "shift", "spark", "spire", "surge", "trail"
        ]
        precondition(prefixes.count * suffixes.count == 2048, "Word matrix must produce 2048 entries")
        var words: [String] = []
        for prefix in prefixes {
            for suffix in suffixes {
                words.append(prefix + suffix)
            }
        }
        return words
    }
}
