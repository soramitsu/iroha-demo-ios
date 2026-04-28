//
//  Example_PointTests.swift
//  Example-PointTests
//
//  Created by Kaji Satoshi on 2016/12/08.
//  Copyright © 2016年 Soramitsu Co., Ltd. All rights reserved.
//

import XCTest
import Foundation
import KeychainAccess
import IrohaSwift
@testable import Example_Point

private func testKeypair(seed: UInt8) -> Keypair {
    try! Keypair(privateKeyBytes: Data(repeating: seed == 0 ? 1 : seed, count: 32))
}

private func testAccountId(seed: UInt8) -> String {
    AccountId.make(publicKey: testKeypair(seed: seed).publicKey)
}

private func testPublicKeyHex(seed: UInt8) -> String {
    testKeypair(seed: seed).publicKey.hexEncodedString()
}

private func testPrivateKeyHex(seed: UInt8) -> String {
    testKeypair(seed: seed).privateKeyBytes.hexEncodedString()
}

final class Example_PointTests: XCTestCase {
    private final class InMemoryStore: KeyValueStore {
        private var storage: [String: String] = [:]

        subscript(key: String) -> String? {
            get { storage[key] }
            set { storage[key] = newValue }
        }
    }

    private func makeAccount(_ index: Int,
                             mnemonic: String? = "test",
                             accountAlias: String? = nil,
                             displayName: String? = nil) -> StoredAccount {
        let seed = UInt8(index + 1)
        return StoredAccount(accountId: testAccountId(seed: seed),
                      accountAlias: accountAlias,
                      displayName: displayName ?? "User \(index)",
                      publicKeyHex: testPublicKeyHex(seed: seed),
                      privateKeyHex: testPrivateKeyHex(seed: seed),
                      recoveryMnemonic: mnemonic,
                      backupDestinations: [.manual])
    }

    func testKeychainAccountStoreSupportsMultipleAccounts() throws {
        let store = KeychainAccountStore(store: InMemoryStore())

        let first = makeAccount(1)
        let second = makeAccount(2)

        store.save(account: first, makeActive: true)
        XCTAssertEqual(store.activeAccount?.accountId, first.accountId)

        store.save(account: second, makeActive: true)
        XCTAssertEqual(store.activeAccount?.accountId, second.accountId)
        XCTAssertEqual(store.accounts.count, 2)

        _ = store.switchAccount(to: first.accountId)
        XCTAssertEqual(store.activeAccount?.accountId, first.accountId)
        XCTAssertEqual(store.accounts.map(\.accountId).sorted(), [first.accountId, second.accountId].sorted())
    }

    func testKeychainAccountStorePersistsActiveAccountAcrossInstances() throws {
        let memoryStore = InMemoryStore()

        let initialStore = KeychainAccountStore(store: memoryStore)
        let first = makeAccount(1)
        let second = makeAccount(2)

        initialStore.save(account: first, makeActive: true)
        initialStore.save(account: second, makeActive: false)

        let reloadedStore = KeychainAccountStore(store: memoryStore)
        XCTAssertEqual(reloadedStore.accounts.count, 2)
        XCTAssertEqual(reloadedStore.activeAccount?.accountId, first.accountId)
    }

    func testStoredAccountDisplayTitleFallsBackToAccountId() {
        let account = makeAccount(3, mnemonic: nil, accountAlias: nil, displayName: "   ")
        XCTAssertEqual(account.displayTitle, account.accountId)
    }

    func testStoredAccountDisplayTitlePrefersOnChainAlias() {
        let account = makeAccount(4, mnemonic: nil, accountAlias: "treasury@banking.retail", displayName: "Treasury")
        XCTAssertEqual(account.displayTitle, "treasury@banking.retail")
        XCTAssertEqual(account.receiveAddressLiteral, "treasury@banking.retail")
    }

    func testStoredAccountShortAccountIdCondensesCanonicalI105() {
        let account = makeAccount(5, mnemonic: nil, displayName: nil)
        XCTAssertEqual(account.shortAccountId, "\(account.accountId.prefix(6))...\(account.accountId.suffix(4))")
    }

    func testStoredAccountMigratesLegacyAliasShapedAccountIdUsingPublicKey() {
        let seed: UInt8 = 42
        let account = StoredAccount(accountId: "legacy@retail",
                                    displayName: "legacy@retail",
                                    publicKeyHex: testPublicKeyHex(seed: seed),
                                    privateKeyHex: testPrivateKeyHex(seed: seed),
                                    recoveryMnemonic: nil,
                                    backupDestinations: [])
        XCTAssertEqual(account.accountId, testAccountId(seed: seed))
        XCTAssertEqual(account.accountAlias, "legacy@retail")
    }

    func testAccountIdentityCanonicalizesAliasAndI105() {
        let accountId = testAccountId(seed: 43)
        XCTAssertEqual(AccountIdentity.normalizedAccountId(accountId), accountId)
        XCTAssertEqual(AccountIdentity.normalizedAlias("Treasury@Banking.Retail"), "treasury@banking.retail")
        XCTAssertNil(AccountIdentity.normalizedReference("not-an-account"))
    }

    @MainActor
    func testToriiServiceNativeSupportOverride() {
        #if DEBUG
        ToriiService.nativeSupportOverride = false
        XCTAssertFalse(ToriiService.shared.canSubmitTransactions)
        ToriiService.nativeSupportOverride = true
        XCTAssertTrue(ToriiService.shared.canSubmitTransactions)
        ToriiService.nativeSupportOverride = nil
        #endif
    }
}

final class MnemonicGridFormatterTests: XCTestCase {
    func testGridProducesRowsWithIndices() {
        let words = (1...12).map { "word\($0)" }
        let rows = MnemonicGridFormatter.grid(words: words, columns: 3)
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows.first?.first?.index, 1)
        XCTAssertEqual(rows.last?.last?.index, 12)
        XCTAssertEqual(rows.last?.last?.word, "word12")
    }

    func testGridHonorsCustomColumnCount() {
        let words = (1...24).map { "w\($0)" }
        let rows = MnemonicGridFormatter.grid(words: words, columns: 4)
        XCTAssertEqual(rows.count, 6)
        XCTAssertEqual(rows[0].count, 4)
        XCTAssertEqual(rows[5].count, 4)
        XCTAssertEqual(rows[5][3].index, 24)
        XCTAssertEqual(rows[5][3].word, "w24")
    }
}

final class IrohaWalletConnectRequestTests: XCTestCase {
    func testParsesWalletTokenAndNodeURL() throws {
        let sid = makeSidBase64URL()
        let url = try XCTUnwrap(URL(string: "iroha://connect?sid=\(sid)&token_wallet=wallet-token&node=https%3A%2F%2Ftorii.soramitsu.io"))
        let request = try IrohaWalletConnectRequest(url: url)
        XCTAssertEqual(request.sidBase64Url, sid)
        XCTAssertEqual(request.token, "wallet-token")
        XCTAssertEqual(request.sessionID.count, 32)
        XCTAssertEqual(request.baseURL.host, "torii.soramitsu.io")
    }

    func testParsesLegacyTokenField() throws {
        let sid = makeSidBase64URL()
        let url = try XCTUnwrap(URL(string: "iroha://connect?sid=\(sid)&token=legacy-token"))
        let request = try IrohaWalletConnectRequest(url: url)
        XCTAssertEqual(request.token, "legacy-token")
    }

    func testApprovePreimageIncludesCanonicalPrefixAndInputs() {
        let sid = Data(repeating: 0x01, count: 32)
        let appKey = Data(repeating: 0x02, count: 32)
        let walletKey = Data(repeating: 0x03, count: 32)
        let accountID = testAccountId(seed: 55)
        let preimage = IrohaWalletConnectSessionCoordinator.makeApprovePreimage(sessionID: sid,
                                                                                 appPublicKey: appKey,
                                                                                 walletPublicKey: walletKey,
                                                                                 accountID: accountID)
        XCTAssertTrue(preimage.starts(with: Data("iroha-connect|approve|".utf8)))
        XCTAssertNotNil(preimage.range(of: sid))
        XCTAssertNotNil(preimage.range(of: appKey))
        XCTAssertNotNil(preimage.range(of: walletKey))
        XCTAssertNotNil(preimage.range(of: Data(accountID.utf8)))
    }

    private func makeSidBase64URL() -> String {
        Data((0..<32).map(UInt8.init))
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

@MainActor
final class OfflinePaymentManagerTests: XCTestCase {
    private struct OfflineAllowanceDTO: Codable {
        let certificateIdHex: String
        let controllerId: String
        let controllerDisplay: String
        let assetId: String
        let registeredAtMs: UInt64
        let expiresAtMs: UInt64
        let policyExpiresAtMs: UInt64
        let refreshAtMs: UInt64?
        let verdictIdHex: String?
        let attestationNonceHex: String?
        let remainingAmount: String
        let deadlineKind: String?
        let deadlineState: String?
        let deadlineMs: UInt64?
        let deadlineMsRemaining: Int64?
        let record: ToriiJSONValue

        init(from item: ToriiOfflineAllowanceItem) {
            certificateIdHex = item.certificateIdHex
            controllerId = item.controllerId
            controllerDisplay = item.controllerDisplay
            assetId = item.assetId
            registeredAtMs = item.registeredAtMs
            expiresAtMs = item.expiresAtMs
            policyExpiresAtMs = item.policyExpiresAtMs
            refreshAtMs = item.refreshAtMs
            verdictIdHex = item.verdictIdHex
            attestationNonceHex = item.attestationNonceHex
            remainingAmount = item.remainingAmount
            deadlineKind = item.deadlineKind
            deadlineState = item.deadlineState
            deadlineMs = item.deadlineMs
            deadlineMsRemaining = item.deadlineMsRemaining
            record = item.record
        }
    }

    private struct OfflineListPayload: Codable {
        let items: [OfflineAllowanceDTO]
        let total: UInt64
    }

    @MainActor
    private final class StubSubmitter: OfflineRedemptionSubmitting {
        let isMockSubmission: Bool
        private(set) var submittedCount = 0

        init(isMockSubmission: Bool = false) {
            self.isMockSubmission = isMockSubmission
        }

        func submitRedeemedVouchers(_ vouchers: [OfflinePaymentVoucher]) async throws -> OfflinePaymentManager.OfflineTransferReceipt {
            submittedCount += 1
            let total = vouchers.reduce(Decimal.zero) { partial, voucher in
                partial + (Decimal(string: voucher.amount) ?? .zero)
            }
            return OfflinePaymentManager.OfflineTransferReceipt(movedAmount: total,
                                                                voucherCount: vouchers.count,
                                                                completedAt: Date())
        }
    }

    @MainActor
    private struct StubOfflineService: OfflineAllowanceProviding {
        let config: ToriiConfiguration
        let allowances: [ToriiOfflineAllowanceItem]

        func fetchOfflineAllowances(limit: UInt64,
                                    includeExpired: Bool) async throws -> ToriiOfflineAllowanceList {
            let payload = OfflineListPayload(items: allowances.map(OfflineAllowanceDTO.init),
                                             total: UInt64(allowances.count))
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            let data = try encoder.encode(payload)
            return try JSONDecoder().decode(ToriiOfflineAllowanceList.self, from: data)
        }
    }

    @MainActor
    private struct StubTransferProvider: OfflineTransferListing {
        let list: ToriiOfflineTransferList

        func fetchOfflineTransfers(limit: UInt64,
                                   filter: String?,
                                   controllerAccountId: String?,
                                   receiverAccountId: String?,
                                   depositAccountId: String?) async throws -> ToriiOfflineTransferList {
            list
        }
    }

    @MainActor
    private final class CapturingTransferProvider: OfflineTransferListing {
        let list: ToriiOfflineTransferList
        private(set) var capturedDeposit: String?
        private(set) var capturedController: String?
        private(set) var capturedReceiver: String?

        init(list: ToriiOfflineTransferList) {
            self.list = list
        }

        func fetchOfflineTransfers(limit: UInt64,
                                   filter: String?,
                                   controllerAccountId: String?,
                                   receiverAccountId: String?,
                                   depositAccountId: String?) async throws -> ToriiOfflineTransferList {
            capturedDeposit = depositAccountId
            capturedController = controllerAccountId
            capturedReceiver = receiverAccountId
            return list
        }
    }

    private var senderAccountId: String { testAccountId(seed: 90) }
    private var controllerAccountId: String { testAccountId(seed: 91) }
    private var receiverAccountId: String { testAccountId(seed: 92) }
    private var depositAccountId: String { testAccountId(seed: 93) }

    private func makeAllowance(id: String = "cert1",
                               remaining: String = "10") -> ToriiOfflineAllowanceItem {
        ToriiOfflineAllowanceItem(certificateIdHex: id,
                                  controllerId: controllerAccountId,
                                  controllerDisplay: "controller",
                                  assetId: "iroha#wonderland",
                                  registeredAtMs: 0,
                                  expiresAtMs: 0,
                                  policyExpiresAtMs: 0,
                                  refreshAtMs: nil,
                                  verdictIdHex: nil,
                                  attestationNonceHex: nil,
                                  remainingAmount: remaining,
                                  deadlineKind: nil,
                                  deadlineState: nil,
                                  deadlineMs: nil,
                                  deadlineMsRemaining: nil,
                                  record: .object([:]))
    }

    func testVoucherCreationConsumesAllowance() async throws {
        let service = StubOfflineService(config: ToriiConfiguration(baseURL: URL(string: "https://example.com")!,
                                                                    chainId: "chain",
                                                                    assetDefinitionId: "iroha#wonderland",
                                                                    defaultDomain: "wonderland",
                                                                    unit: "IRH"),
                                         allowances: [makeAllowance(remaining: "5")])

        let journalURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("offline_journal_tests_\(UUID().uuidString).bin")
        let manager = OfflinePaymentManager(service: service,
                                            journalURL: journalURL,
                                            journalKeySeed: Data(repeating: 1, count: 32),
                                            accountResolver: { self.senderAccountId })
        _ = try await manager.refreshAllowances()
        XCTAssertEqual(manager.totalRemaining, Decimal(string: "5"))
        let voucher = try manager.createVoucher(receiverId: "merchant@wonderland",
                                                amount: Decimal(string: "3")!,
                                                note: nil,
                                                mode: .ledgerReconcilable)
        XCTAssertEqual(voucher.receiverId, "merchant@wonderland")
        XCTAssertEqual(manager.totalRemaining, Decimal(string: "2"))
    }

    func testVoucherCreationRespectsSingleCertificateLimit() async throws {
        let service = StubOfflineService(config: ToriiConfiguration(baseURL: URL(string: "https://example.com")!,
                                                                    chainId: "chain",
                                                                    assetDefinitionId: "iroha#wonderland",
                                                                    defaultDomain: "wonderland",
                                                                    unit: "IRH"),
                                         allowances: [
                                             makeAllowance(id: "cert-a", remaining: "1000"),
                                             makeAllowance(id: "cert-b", remaining: "2000")
                                         ])

        let journalURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("offline_journal_tests_\(UUID().uuidString).bin")
        let manager = OfflinePaymentManager(service: service,
                                            journalURL: journalURL,
                                            journalKeySeed: Data(repeating: 8, count: 32),
                                            accountResolver: { self.senderAccountId })
        _ = try await manager.refreshAllowances()
        XCTAssertEqual(manager.totalRemaining, Decimal(string: "3000"))
        XCTAssertEqual(manager.maxSingleRemaining, Decimal(string: "2000"))
        XCTAssertThrowsError(
            try manager.createVoucher(
                receiverId: "merchant@wonderland",
                amount: Decimal(string: "3000")!,
                note: nil,
                mode: .ledgerReconcilable
            )
        ) { error in
            guard case OfflinePaymentError.insufficientAllowance = error else {
                XCTFail("unexpected error: \(error)")
                return
            }
        }
    }

    func testVoucherFailsWhenAllowancesMissing() throws {
        let service = StubOfflineService(config: ToriiConfiguration(baseURL: URL(string: "https://example.com")!,
                                                                    chainId: "chain",
                                                                    assetDefinitionId: "iroha#wonderland",
                                                                    defaultDomain: "wonderland",
                                                                    unit: "IRH"),
                                         allowances: [])
        let journalURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("offline_journal_tests_\(UUID().uuidString).bin")
        let manager = OfflinePaymentManager(service: service,
                                            journalURL: journalURL,
                                            journalKeySeed: Data(repeating: 2, count: 32),
                                           accountResolver: { self.senderAccountId })
        XCTAssertThrowsError(try manager.createVoucher(receiverId: "merchant@wonderland",
                                                       amount: Decimal(string: "1")!,
                                                       note: nil,
                                                       mode: .ledgerReconcilable))
    }

    func testVoucherRedemptionPreventsDuplicates() async throws {
        let service = StubOfflineService(config: ToriiConfiguration(baseURL: URL(string: "https://example.com")!,
                                                                    chainId: "chain",
                                                                    assetDefinitionId: "iroha#wonderland",
                                                                    defaultDomain: "wonderland",
                                                                    unit: "IRH"),
                                         allowances: [makeAllowance(remaining: "2")])
        let suite = UserDefaults(suiteName: "offline.tests.\(UUID().uuidString)")!
        let journalURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("offline_journal_tests_\(UUID().uuidString).bin")
        let manager = OfflinePaymentManager(service: service,
                                            journalURL: journalURL,
                                            journalKeySeed: Data(repeating: 3, count: 32),
                                            accountResolver: { self.senderAccountId },
                                            redeemedStore: suite)
        _ = try await manager.refreshAllowances()
        let voucher = try manager.createVoucher(receiverId: "merchant@wonderland",
                                                amount: Decimal(string: "1")!,
                                                note: "coffee",
                                                mode: .ledgerReconcilable)
        guard let payload = voucher.qrPayloadString else {
            return XCTFail("Missing payload")
        }
        let validated = try manager.validateVoucherPayload(payload)
        XCTAssertEqual(validated.receiverId, "merchant@wonderland")
        manager.markVoucherRedeemed(voucher)
        XCTAssertThrowsError(try manager.validateVoucherPayload(payload))
        XCTAssertEqual(manager.redeemedTotal, Decimal(string: "1"))
        XCTAssertNotNil(manager.exportRedeemedJSON())
        let receipt = try manager.simulateOnlineTransfer()
        XCTAssertEqual(receipt.voucherCount, 1)
        XCTAssertEqual(receipt.movedAmount, Decimal(string: "1"))
        XCTAssertEqual(manager.redeemedTotal, .zero)
        XCTAssertNil(manager.exportRedeemedJSON())
    }

    func testSimulateTransferRequiresRedeemedVouchers() {
        let service = StubOfflineService(config: ToriiConfiguration(baseURL: URL(string: "https://example.com")!,
                                                                    chainId: "chain",
                                                                    assetDefinitionId: "iroha#wonderland",
                                                                    defaultDomain: "wonderland",
                                                                    unit: "IRH"),
                                         allowances: [])
        let manager = OfflinePaymentManager(service: service,
                                            journalURL: nil,
                                            journalKeySeed: Data(repeating: 4, count: 32),
                                            accountResolver: { self.senderAccountId },
                                            redeemedStore: UserDefaults(suiteName: "offline.tests.empty.\(UUID().uuidString)")!)
        XCTAssertThrowsError(try manager.simulateOnlineTransfer()) { error in
            XCTAssertEqual(error.localizedDescription, OfflinePaymentError.nothingToTransfer.localizedDescription)
        }
    }

    func testSubmitterPathClearsRedeemedState() async throws {
        let service = StubOfflineService(config: ToriiConfiguration(baseURL: URL(string: "https://example.com")!,
                                                                    chainId: "chain",
                                                                    assetDefinitionId: "iroha#wonderland",
                                                                    defaultDomain: "wonderland",
                                                                    unit: "IRH"),
                                         allowances: [makeAllowance(remaining: "2")])
        let suite = UserDefaults(suiteName: "offline.tests.submitter.\(UUID().uuidString)")!
        let submitter = StubSubmitter(isMockSubmission: false)
        let journalURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("offline_journal_tests_\(UUID().uuidString).bin")
        let manager = OfflinePaymentManager(service: service,
                                            journalURL: journalURL,
                                            journalKeySeed: Data(repeating: 7, count: 32),
                                            accountResolver: { self.senderAccountId },
                                            redeemedStore: suite,
                                            submitter: submitter)
        _ = try await manager.refreshAllowances()
        let voucher = try manager.createVoucher(receiverId: "receiver@wonderland",
                                                amount: Decimal(string: "1")!,
                                                note: "test",
                                                mode: .ledgerReconcilable)
        manager.markVoucherRedeemed(voucher)
        let receipt = try await manager.transferRedeemedToOnline()
        XCTAssertEqual(receipt.voucherCount, 1)
        XCTAssertEqual(receipt.movedAmount, Decimal(string: "1"))
        XCTAssertEqual(submitter.submittedCount, 1)
        XCTAssertTrue(manager.redeemedVouchers().isEmpty)
        XCTAssertNil(manager.exportRedeemedJSON())
    }

    func testInvalidPayloadFailsValidation() {
        let service = StubOfflineService(config: ToriiConfiguration(baseURL: URL(string: "https://example.com")!,
                                                                    chainId: "chain",
                                                                    assetDefinitionId: "iroha#wonderland",
                                                                    defaultDomain: "wonderland",
                                                                    unit: "IRH"),
                                         allowances: [])
        let manager = OfflinePaymentManager(service: service,
                                            journalURL: nil,
                                            journalKeySeed: Data(repeating: 5, count: 32),
                                            accountResolver: { self.senderAccountId },
                                            redeemedStore: UserDefaults(suiteName: "offline.tests.invalid.\(UUID().uuidString)")!)
        XCTAssertThrowsError(try manager.validateVoucherPayload("not json"))
    }

    func testRedeemedExportAndClear() async throws {
        let service = StubOfflineService(config: ToriiConfiguration(baseURL: URL(string: "https://example.com")!,
                                                                    chainId: "chain",
                                                                    assetDefinitionId: "iroha#wonderland",
                                                                    defaultDomain: "wonderland",
                                                                    unit: "IRH"),
                                         allowances: [makeAllowance(remaining: "2")])
        let suite = UserDefaults(suiteName: "offline.tests.export.\(UUID().uuidString)")!
        let journalURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("offline_journal_tests_\(UUID().uuidString).bin")
        let manager = OfflinePaymentManager(service: service,
                                            journalURL: journalURL,
                                            journalKeySeed: Data(repeating: 6, count: 32),
                                            accountResolver: { self.senderAccountId },
                                            redeemedStore: suite)
        _ = try await manager.refreshAllowances()
        let voucher = try manager.createVoucher(receiverId: "receiver@wonderland",
                                                amount: Decimal(string: "1")!,
                                                note: nil,
                                                mode: .ledgerReconcilable)
        guard let payload = voucher.qrPayloadString else {
            return XCTFail("Missing payload")
        }
        manager.markVoucherRedeemed(voucher)
        XCTAssertNotNil(manager.exportRedeemedJSON(pretty: false))
        XCTAssertTrue(manager.isVoucherRedeemed(voucher))
        XCTAssertThrowsError(try manager.validateVoucherPayload(payload))
        manager.clearRedeemed()
        XCTAssertEqual(manager.redeemedVouchers().count, 0)
        XCTAssertNil(manager.exportRedeemedJSON())
    }

    func testFetchRemoteTransfersRequiresProvider() async throws {
        let service = StubOfflineService(config: ToriiConfiguration(baseURL: URL(string: "https://example.com")!,
                                                                    chainId: "chain",
                                                                    assetDefinitionId: "iroha#wonderland",
                                                                    defaultDomain: "wonderland",
                                                                    unit: "IRH"),
                                         allowances: [])
        let manager = OfflinePaymentManager(service: service,
                                            journalURL: nil,
                                            journalKeySeed: Data(repeating: 9, count: 32),
                                            accountResolver: { self.senderAccountId },
                                            redeemedStore: UserDefaults(suiteName: "offline.tests.transfers.none.\(UUID().uuidString)")!)
        do {
            _ = try await manager.fetchRemoteTransfers(limit: 1)
            XCTFail("Expected apiUnavailable")
        } catch {
            XCTAssertEqual(error.localizedDescription, OfflinePaymentError.apiUnavailable.localizedDescription)
        }
    }

    func testFetchRemoteTransfersReturnsList() async throws {
        let service = StubOfflineService(config: ToriiConfiguration(baseURL: URL(string: "https://example.com")!,
                                                                    chainId: "chain",
                                                                    assetDefinitionId: "iroha#wonderland",
                                                                    defaultDomain: "wonderland",
                                                                    unit: "IRH"),
                                         allowances: [])
        let transferList = try makeTransferList()
        let provider = StubTransferProvider(list: transferList)
        let manager = OfflinePaymentManager(service: service,
                                            journalURL: nil,
                                            journalKeySeed: Data(repeating: 10, count: 32),
                                            accountResolver: { self.senderAccountId },
                                            redeemedStore: UserDefaults(suiteName: "offline.tests.transfers.\(UUID().uuidString)")!,
                                            transferProvider: provider)
        let remoteList = try await manager.fetchRemoteTransfers(limit: 2)
        XCTAssertEqual(remoteList.total, 1)
        XCTAssertEqual(remoteList.items.first?.bundleIdHex, "abcd1234")
        XCTAssertEqual(remoteList.items.first?.depositAccountId, depositAccountId)
    }

    func testRemoteTransferDefaultsDepositAccount() async throws {
        let service = StubOfflineService(config: ToriiConfiguration(baseURL: URL(string: "https://example.com")!,
                                                                    chainId: "chain",
                                                                    assetDefinitionId: "iroha#wonderland",
                                                                    defaultDomain: "wonderland",
                                                                    unit: "IRH"),
                                         allowances: [])
        let transferList = try makeTransferList()
        let provider = CapturingTransferProvider(list: transferList)
        let manager = OfflinePaymentManager(service: service,
                                            journalURL: nil,
                                            journalKeySeed: Data(repeating: 11, count: 32),
                                            accountResolver: { self.depositAccountId },
                                            redeemedStore: UserDefaults(suiteName: "offline.tests.transfers.capture.\(UUID().uuidString)")!,
                                            transferProvider: provider)
        _ = try await manager.fetchRemoteTransfers(limit: 3)
        XCTAssertEqual(provider.capturedDeposit, depositAccountId)
        XCTAssertEqual(provider.capturedController, depositAccountId)
        XCTAssertEqual(provider.capturedReceiver, depositAccountId)
    }

    private func makeTransferList() throws -> ToriiOfflineTransferList {
        let payload: [String: Any] = [
            "items": [[
                "bundle_id_hex": "abcd1234",
                "controller_id": controllerAccountId,
                "controller_display": "controller",
                "receiver_id": receiverAccountId,
                "receiver_display": "receiver",
                "deposit_account_id": depositAccountId,
                "deposit_account_display": "deposit",
                "asset_id": "iroha#wonderland",
                "receipt_count": 1,
                "total_amount": "1",
                "claimed_delta": "1",
                "status": "pending",
                "recorded_at_ms": 1,
                "recorded_at_height": 1,
                "archived_at_height": NSNull(),
                "certificate_id_hex": "deadbeef",
                "transfer": [:]
            ]],
            "total": 1
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        return try JSONDecoder().decode(ToriiOfflineTransferList.self, from: data)
    }
}

final class SubscriptionHubTests: XCTestCase {
    func testSubscriptionAmountFormatterFixedAmount() {
        let label = SubscriptionAmountFormatter.label(amount: Decimal(string: "1500"),
                                                      maxAmount: nil,
                                                      type: .fixed,
                                                      unit: "IRH")
        XCTAssertTrue(label.contains("IRH"))
        let digits = label.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        XCTAssertEqual(digits, "1500")
    }

    func testSubscriptionAmountFormatterVariableUsesMax() {
        let label = SubscriptionAmountFormatter.label(amount: nil,
                                                      maxAmount: Decimal(string: "9000"),
                                                      type: .variable,
                                                      unit: "IRH")
        XCTAssertTrue(label.contains("IRH"))
        XCTAssertTrue(label.contains("上限"))
        let digits = label.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        XCTAssertEqual(digits, "9000")
    }

    func testSubscriptionScheduleAdvanceAddsMonths() {
        let calendar = Calendar.current
        let date = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15)) ?? Date()
        let advanced = SubscriptionSchedule.advance(from: date, cadence: .monthly)
        let month = calendar.component(.month, from: advanced)
        XCTAssertEqual(month, 2)
    }

    func testSubscriptionAutoDeductAdvancesNextPaymentDate() {
        let calendar = Calendar(identifier: .gregorian)
        let chargeDate = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1)) ?? Date()
        let now = calendar.date(from: DateComponents(year: 2026, month: 2, day: 20)) ?? Date()
        var records = [
            SubscriptionRecord(id: UUID(),
                               merchantName: "Netflix",
                               amount: Decimal(string: "1500"),
                               maxAmount: nil,
                               amountType: .fixed,
                               cadence: .monthly,
                               nextPaymentDate: chargeDate,
                               status: .active,
                               cancelAtPeriodEnd: false,
                               lastChargeDate: nil,
                               lastChargeAmount: nil,
                               note: nil)
        ]
        let changed = SubscriptionBilling.applyAutoDeductions(&records, now: now)
        XCTAssertTrue(changed)
        XCTAssertEqual(records[0].lastChargeDate, chargeDate)
        XCTAssertNotNil(records[0].lastChargeAmount)
        XCTAssertTrue(records[0].nextPaymentDate > chargeDate)
    }

    func testSubscriptionAutoDeductCancelsAtPeriodEnd() {
        let calendar = Calendar(identifier: .gregorian)
        let chargeDate = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1)) ?? Date()
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10)) ?? Date()
        var records = [
            SubscriptionRecord(id: UUID(),
                               merchantName: "News",
                               amount: Decimal(string: "800"),
                               maxAmount: nil,
                               amountType: .fixed,
                               cadence: .monthly,
                               nextPaymentDate: chargeDate,
                               status: .active,
                               cancelAtPeriodEnd: true,
                               lastChargeDate: nil,
                               lastChargeAmount: nil,
                               note: nil)
        ]
        _ = SubscriptionBilling.applyAutoDeductions(&records, now: now)
        XCTAssertEqual(records[0].status, .canceled)
        XCTAssertFalse(records[0].cancelAtPeriodEnd)
        XCTAssertEqual(records[0].lastChargeDate, chargeDate)
    }
}
