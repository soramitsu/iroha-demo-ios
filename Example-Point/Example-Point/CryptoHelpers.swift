import Foundation

extension Data {
    func hexEncodedString() -> String {
        map { String(format: "%02x", $0) }.joined()
    }

    init?(hexString: String) {
        let sanitized = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sanitized.count % 2 == 0 else { return nil }
        var data = Data(capacity: sanitized.count / 2)
        var index = sanitized.startIndex
        while index < sanitized.endIndex {
            let next = sanitized.index(index, offsetBy: 2)
            let byteString = sanitized[index..<next]
            guard let byte = UInt8(byteString, radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}

extension Decimal {
    var plainString: String {
        NSDecimalNumber(decimal: self).stringValue
    }

    static func from(quantity: String) -> Decimal {
        Decimal(string: quantity) ?? .zero
    }
}
