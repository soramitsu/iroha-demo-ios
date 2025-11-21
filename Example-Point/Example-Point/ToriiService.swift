import Foundation
import IrohaSwift
import UIKit

struct WalletSnapshot {
    let balances: [ToriiAssetBalance]
    let transactions: [ToriiTxItem]

    var primaryBalance: ToriiAssetBalance? {
        balances.first
    }
}

enum ToriiServiceError: Error, LocalizedError {
    case credentialsMissing
    case invalidPrivateKey
    case invalidReceiver

    var errorDescription: String? {
        switch self {
        case .credentialsMissing:
            return "Account credentials are missing. Please register again."
        case .invalidPrivateKey:
            return "Stored private key is invalid."
        case .invalidReceiver:
            return "Receiver account id is invalid."
        }
    }
}

@MainActor
final class ToriiService {
    static let shared = ToriiService()

    let config: ToriiConfiguration
    private let toriiClient: ToriiClient
    private let sdk: IrohaSDK

    private init(configuration: ToriiConfiguration = .load()) {
        self.config = configuration
        self.toriiClient = ToriiClient(baseURL: configuration.baseURL)
        self.sdk = IrohaSDK(baseURL: configuration.baseURL)
    }

    func fetchSnapshot(accountId: String) async throws -> WalletSnapshot {
        async let balances = toriiClient.getAssets(accountId: accountId, limit: 50)
        async let transactions = toriiClient.getTransactions(accountId: accountId, limit: 50)
        let resolvedBalances = try await balances
        let resolvedTransactions = try await transactions
        return WalletSnapshot(balances: resolvedBalances,
                              transactions: resolvedTransactions.items)
    }

    func registerAccount(displayName: String,
                         material: SoraNexusKeyMaterial) async throws -> ToriiAccountOnboardingResponse {
        let keypair = material.keypair
        let accountId = accountId(for: keypair)
        let identity: [String: String] = await MainActor.run {
            var deviceIdentity: [String: String] = [
                "platform": "iOS",
                "system_version": UIDevice.current.systemVersion,
                "locale": Locale.current.identifier
            ]
            deviceIdentity["device"] = UIDevice.current.model
            if let bundleId = Bundle.main.bundleIdentifier {
                deviceIdentity["bundle_id"] = bundleId
            }
            return deviceIdentity
        }
        let request = ToriiAccountOnboardingRequest(alias: displayName,
                                                    accountId: accountId,
                                                    identity: identity)
        let response = try await toriiClient.registerAccount(request)
        KeychainManager.instance.privateKeyHex = material.privateKeyHex
        KeychainManager.instance.publicKeyHex = material.publicKeyHex
        KeychainManager.instance.accountId = response.accountId
        KeychainManager.instance.displayName = displayName
        KeychainManager.instance.recoveryMnemonic = material.phrase
        return response
    }

    func submitTransfer(amount: Decimal,
                        receiverAccountId: String,
                        memo: String? = nil) async throws -> ToriiPipelineTransactionStatus {
        guard let privateKeyHex = KeychainManager.instance.privateKeyHex,
              let privateKeyData = Data(hexString: privateKeyHex) else {
            throw ToriiServiceError.credentialsMissing
        }
        guard let accountId = KeychainManager.instance.accountId else {
            throw ToriiServiceError.credentialsMissing
        }
        let sanitizedReceiver = receiverAccountId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedReceiver.isEmpty else {
            throw ToriiServiceError.invalidReceiver
        }
        let keypair: Keypair
        do {
            keypair = try Keypair(privateKeyBytes: privateKeyData)
        } catch {
            throw ToriiServiceError.invalidPrivateKey
        }
        let request = TransferRequest(chainId: config.chainId,
                                      authority: accountId,
                                      assetDefinitionId: config.assetDefinitionId,
                                      quantity: amount.plainString,
                                      destination: sanitizedReceiver,
                                      description: memo,
                                      ttlMs: 60_000)
        return try await sdk.submitAndWait(transfer: request, keypair: keypair)
    }

    func accountId(for keypair: Keypair) -> String {
        config.accountId(for: keypair.publicKey)
    }

    func parseBalance(from balances: [ToriiAssetBalance]) -> Decimal {
        guard let primary = preferredBalance(in: balances) else { return .zero }
        return Decimal.from(quantity: primary.quantity)
    }

    private func preferredBalance(in balances: [ToriiAssetBalance]) -> ToriiAssetBalance? {
        balances.first { entry in
            entry.asset_id.localizedCaseInsensitiveContains(config.assetDefinitionId)
        } ?? balances.first
    }
}
