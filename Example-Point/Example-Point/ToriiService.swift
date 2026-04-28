import Foundation
import IrohaSwift
import UIKit

enum AccountIdentity {
    static func normalizedAccountId(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("@") else {
            return nil
        }
        guard let address = try? AccountAddress.parseEncoded(trimmed, expectedPrefix: AccountId.defaultNetworkPrefix),
              let i105 = try? address.toI105(networkPrefix: AccountId.defaultNetworkPrefix) else {
            return nil
        }
        return i105
    }

    static func normalizedAlias(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed == raw,
              !trimmed.contains(where: \.isWhitespace),
              !trimmed.unicodeScalars.contains(where: { $0.properties.isControl }) else {
            return nil
        }
        let canonical = trimmed.lowercased()
        let parts = canonical.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2,
              !parts[0].isEmpty,
              !parts[1].isEmpty else {
            return nil
        }

        let suffix = parts[1].split(separator: ".", omittingEmptySubsequences: false)
        guard suffix.count == 1 || suffix.count == 2,
              suffix.allSatisfy({ !$0.isEmpty }) else {
            return nil
        }
        return canonical
    }

    static func normalizedReference(_ raw: String) -> String? {
        normalizedAccountId(raw) ?? normalizedAlias(raw)
    }

    static func isAlias(_ raw: String?) -> Bool {
        normalizedAlias(raw) != nil
    }
}

struct ResolvedAccountReference {
    let literal: String
    let accountId: String
    let alias: String?
}

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
    case nativeBridgeUnavailable

    var errorDescription: String? {
        switch self {
        case .credentialsMissing:
            return "Account credentials are missing. Please register again."
        case .invalidPrivateKey:
            return "Stored private key is invalid."
        case .invalidReceiver:
            return "送信先のアカウントIDまたはエイリアスが不正です。"
        case .nativeBridgeUnavailable:
            return "Device is missing the required native signer. Please reinstall or contact support."
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

    #if DEBUG
    /// Override for unit testing transaction encoder availability.
    static var nativeSupportOverride: Bool?
    #endif

    var canSubmitTransactions: Bool {
        #if DEBUG
        if let override = ToriiService.nativeSupportOverride {
            return override
        }
        #endif
        return NoritoNativeBridge.shared.supportsTransactions(using: .ed25519)
    }

    func fetchSnapshot(accountId: String) async throws -> WalletSnapshot {
        async let balances = toriiClient.getAssets(accountId: accountId, limit: 50)
        async let transactions = toriiClient.getTransactions(accountId: accountId, limit: 50)
        let resolvedBalances = try await balances
        let resolvedTransactions = try await transactions
        return WalletSnapshot(balances: resolvedBalances,
                              transactions: resolvedTransactions.items)
    }

    func registerAccount(alias: String,
                         material: SoraNexusKeyMaterial,
                         backups: [KeyBackupDestination] = []) async throws -> StoredAccount {
        guard let alias = AccountIdentity.normalizedAlias(alias) else {
            throw ToriiServiceError.invalidReceiver
        }
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
        let request = ToriiAccountOnboardingRequest(alias: alias,
                                                    accountId: accountId,
                                                    identity: identity)
        let response = try await toriiClient.registerAccount(request)
        let account = StoredAccount(accountId: response.accountId,
                                    accountAlias: alias,
                                    displayName: nil,
                                    publicKeyHex: material.publicKeyHex,
                                    privateKeyHex: material.privateKeyHex,
                                    recoveryMnemonic: material.phrase,
                                    backupDestinations: backups)
        KeychainManager.instance.save(account: account, makeActive: true)
        return account
    }

    func resolveAccountReference(_ receiver: String) async throws -> ResolvedAccountReference {
        if let accountId = AccountIdentity.normalizedAccountId(receiver) {
            return ResolvedAccountReference(literal: accountId,
                                            accountId: accountId,
                                            alias: nil)
        }
        guard let alias = AccountIdentity.normalizedAlias(receiver) else {
            throw ToriiServiceError.invalidReceiver
        }
        guard let resolution = try await toriiClient.resolveAccountAlias(alias),
              let canonicalAccountId = AccountIdentity.normalizedAccountId(resolution.accountId) else {
            throw ToriiServiceError.invalidReceiver
        }
        return ResolvedAccountReference(literal: resolution.alias,
                                        accountId: canonicalAccountId,
                                        alias: resolution.alias)
    }

    func submitTransfer(amount: Decimal,
                        receiverAccountId: String,
                        memo: String? = nil) async throws -> ToriiPipelineTransactionStatus {
        guard canSubmitTransactions else {
            throw ToriiServiceError.nativeBridgeUnavailable
        }
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

    // MARK: - Offline allowances

    func fetchOfflineAllowances(limit: UInt64 = 50,
                                includeExpired: Bool = false) async throws -> ToriiOfflineAllowanceList {
        let params = ToriiOfflineListParams(limit: limit,
                                            sort: "-registered_at_ms",
                                            includeExpired: includeExpired)
        return try await toriiClient.listOfflineAllowances(params: params)
    }

    private func preferredBalance(in balances: [ToriiAssetBalance]) -> ToriiAssetBalance? {
        balances.first { entry in
            entry.asset_id.localizedCaseInsensitiveContains(config.assetDefinitionId)
        } ?? balances.first
    }
}

extension ToriiService: OfflineRedemptionSubmitting {
    var isMockSubmission: Bool { true }

    func submitRedeemedVouchers(_ vouchers: [OfflinePaymentVoucher]) async throws -> OfflinePaymentManager.OfflineTransferReceipt {
        guard let accountId = KeychainManager.instance.accountId else {
            throw ToriiServiceError.credentialsMissing
        }
        var params = ToriiOfflineListParams(limit: 1,
                                            sort: "-recorded_at_ms",
                                            includeExpired: false)
        params.depositAccountId = accountId
        params.controllerId = accountId
        params.receiverId = accountId
        _ = try await toriiClient.listOfflineTransfers(params: params)

        let moved = vouchers.reduce(Decimal.zero) { partial, voucher in
            partial + (Decimal(string: voucher.amount) ?? .zero)
        }
        return OfflinePaymentManager.OfflineTransferReceipt(movedAmount: moved,
                                                            voucherCount: vouchers.count,
                                                            completedAt: Date())
    }
}

extension ToriiService: OfflineTransferListing {
    func fetchOfflineTransfers(limit: UInt64,
                               filter: String?,
                               controllerAccountId: String?,
                               receiverAccountId: String?,
                               depositAccountId: String?) async throws -> ToriiOfflineTransferList {
        var params = ToriiOfflineListParams(limit: limit,
                                            sort: "-recorded_at_ms",
                                            includeExpired: false)
        params.filter = filter
        params.controllerId = controllerAccountId
        params.receiverId = receiverAccountId
        params.depositAccountId = depositAccountId
        return try await toriiClient.listOfflineTransfers(params: params)
    }
}
