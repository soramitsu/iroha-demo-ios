import Foundation
import IrohaSwift

struct ToriiConfiguration {
    enum ConfigurationError: Error {
        case missing(key: String)
        case invalidURL(String)
    }

    let baseURL: URL
    let chainId: String
    let assetDefinitionId: String
    let defaultDomain: String
    let unit: String

    static func load(from bundle: Bundle = .main) -> ToriiConfiguration {
        func string(for key: String) -> String {
            guard let value = bundle.object(forInfoDictionaryKey: key) as? String,
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                fatalError("Missing Info.plist key: \(key)")
            }
            return value
        }

        let baseURLString = string(for: "ToriiBaseURL")
        guard let url = URL(string: baseURLString) else {
            fatalError("Invalid ToriiBaseURL: \(baseURLString)")
        }
        let chainId = string(for: "ToriiChainId")
        let assetDefinition = string(for: "ToriiAssetDefinitionId")
        let domain = string(for: "ToriiDefaultDomain")
        let unit = (bundle.object(forInfoDictionaryKey: "Unit") as? String) ?? "IRH"
        return ToriiConfiguration(baseURL: url,
                                  chainId: chainId,
                                  assetDefinitionId: assetDefinition,
                                  defaultDomain: domain,
                                  unit: unit)
    }
}

extension ToriiConfiguration {
    func accountId(for publicKey: Data) -> String {
        AccountId.make(publicKey: publicKey, domain: defaultDomain)
    }

    var assetDisplayName: String {
        assetDefinitionId.split(separator: "#", omittingEmptySubsequences: true).first.map(String.init) ?? assetDefinitionId
    }
}
