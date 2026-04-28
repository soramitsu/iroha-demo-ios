import Foundation
import KeychainAccess

protocol KeyValueStore: AnyObject {
    subscript(key: String) -> String? { get set }
}

extension Keychain: KeyValueStore {}

protocol RemovableKeyValueStore: KeyValueStore {
    func remove(_ key: String) throws
}

extension Keychain: RemovableKeyValueStore {
    func remove(_ key: String) throws {
        try remove(key, ignoringAttributeSynchronizable: true)
    }
}

final class InMemorySecureStore: @unchecked Sendable, RemovableKeyValueStore {
    static let shared = InMemorySecureStore()

    private var storage: [String: String] = [:]
    private let lock = NSLock()

    private init() {}

    subscript(key: String) -> String? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage[key]
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            storage[key] = newValue
        }
    }

    func remove(_ key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        storage[key] = nil
    }
}

struct StoredAccount: Codable, Equatable {
    var accountId: String
    var accountAlias: String?
    var displayName: String?
    var publicKeyHex: String
    var privateKeyHex: String
    var recoveryMnemonic: String?
    var backupDestinations: [KeyBackupDestination]

    init(accountId: String,
         accountAlias: String? = nil,
         displayName: String?,
         publicKeyHex: String,
         privateKeyHex: String,
         recoveryMnemonic: String?,
         backupDestinations: [KeyBackupDestination]) {
        self.accountId = StoredAccount.canonicalAccountId(accountId, publicKeyHex: publicKeyHex)
        self.accountAlias = StoredAccount.canonicalAlias(accountAlias)
            ?? StoredAccount.canonicalAlias(accountId)
            ?? StoredAccount.canonicalAlias(displayName)
        let trimmedDisplayName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let alias = self.accountAlias, trimmedDisplayName == alias {
            self.displayName = nil
        } else {
            self.displayName = trimmedDisplayName?.isEmpty == false ? trimmedDisplayName : nil
        }
        self.publicKeyHex = publicKeyHex
        self.privateKeyHex = privateKeyHex
        self.recoveryMnemonic = recoveryMnemonic
        self.backupDestinations = Array(Set(backupDestinations)).sorted { $0.rawValue < $1.rawValue }
    }

    private enum CodingKeys: String, CodingKey {
        case accountId
        case accountAlias
        case displayName
        case publicKeyHex
        case privateKeyHex
        case recoveryMnemonic
        case backupDestinations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let accountId = try container.decode(String.self, forKey: .accountId)
        let accountAlias = try container.decodeIfPresent(String.self, forKey: .accountAlias)
        let displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        let publicKeyHex = try container.decode(String.self, forKey: .publicKeyHex)
        let privateKeyHex = try container.decode(String.self, forKey: .privateKeyHex)
        let recoveryMnemonic = try container.decodeIfPresent(String.self, forKey: .recoveryMnemonic)
        let backupDestinations = try container.decodeIfPresent([KeyBackupDestination].self, forKey: .backupDestinations) ?? []
        self.init(accountId: accountId,
                  accountAlias: accountAlias,
                  displayName: displayName,
                  publicKeyHex: publicKeyHex,
                  privateKeyHex: privateKeyHex,
                  recoveryMnemonic: recoveryMnemonic,
                  backupDestinations: backupDestinations)
    }

    var displayTitle: String {
        if let alias = accountAlias, !alias.isEmpty {
            return alias
        }
        if let name = displayName, !name.isEmpty {
            return name
        }
        return accountId
    }

    var receiveAddressLiteral: String {
        accountAlias ?? accountId
    }

    var shortAccountId: String {
        let trimmed = accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return accountId }
        if trimmed.count > 14 {
            return "\(trimmed.prefix(6))...\(trimmed.suffix(4))"
        }
        return trimmed
    }

    func matchesSelectionIdentifier(_ literal: String) -> Bool {
        if let normalizedAccountId = AccountIdentity.normalizedAccountId(literal) {
            return normalizedAccountId == accountId
        }
        if let normalizedAlias = AccountIdentity.normalizedAlias(literal) {
            return normalizedAlias == accountAlias
        }
        return false
    }

    private static func canonicalAccountId(_ raw: String, publicKeyHex: String) -> String {
        if let normalized = AccountIdentity.normalizedAccountId(raw) {
            return normalized
        }
        if let publicKeyData = Data(hexString: publicKeyHex) {
            return AccountId.make(publicKey: publicKeyData)
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func canonicalAlias(_ raw: String?) -> String? {
        AccountIdentity.normalizedAlias(raw)
    }
}

final class KeychainAccountStore {
    private let store: KeyValueStore

    private enum Keys {
        static let accounts = "torii.accounts"
        static let activeAccountId = "torii.activeAccountId"
    }

    init(store: KeyValueStore) {
        self.store = store
    }

    var accounts: [StoredAccount] {
        get {
            guard let raw = store[Keys.accounts],
                  let data = Data(base64Encoded: raw) else {
                return []
            }
            return (try? JSONDecoder().decode([StoredAccount].self, from: data)) ?? []
        }
        set {
            guard !newValue.isEmpty else {
                store[Keys.accounts] = nil
                return
            }
            guard let data = try? JSONEncoder().encode(newValue) else {
                return
            }
            store[Keys.accounts] = data.base64EncodedString()
        }
    }

    var activeAccountId: String? {
        get { store[Keys.activeAccountId] }
        set { store[Keys.activeAccountId] = newValue }
    }

    var activeAccount: StoredAccount? {
        let storedAccounts = accounts
        if let activeId = activeAccountId,
           let active = storedAccounts.first(where: { $0.matchesSelectionIdentifier(activeId) }) {
            if active.accountId != activeId {
                activeAccountId = active.accountId
            }
            return active
        }
        return storedAccounts.first
    }

    func save(account: StoredAccount, makeActive: Bool = true) {
        var stored = accounts.filter { $0.accountId != account.accountId }
        stored.append(account)
        accounts = stored
        if makeActive {
            activeAccountId = account.accountId
        }
    }

    @discardableResult
    func switchAccount(to accountId: String) -> StoredAccount? {
        guard let account = accounts.first(where: { $0.matchesSelectionIdentifier(accountId) }) else {
            return nil
        }
        activeAccountId = account.accountId
        return account
    }

    func removeAll() {
        accounts = []
        activeAccountId = nil
    }
}

extension KeychainManager {
    private enum Keys {
        static let accountId = "torii.accountId"
        static let accountAlias = "torii.accountAlias"
        static let privateKey = "torii.privateKey"
        static let publicKey = "torii.publicKey"
        static let displayName = "torii.displayName"
        static let mnemonic = "torii.mnemonic"
        static let backupDestinations = "torii.backupDestinations"
    }

    private var accountStore: KeychainAccountStore {
        KeychainAccountStore(store: secureStore)
    }

    var storedAccounts: [StoredAccount] {
        get { accountStore.accounts }
        set { accountStore.accounts = newValue }
    }

    var activeAccount: StoredAccount? {
        accountStore.activeAccount ?? migrateLegacyAccountIfNeeded()
    }

    func save(account: StoredAccount, makeActive: Bool = true) {
        accountStore.save(account: account, makeActive: makeActive)
        persistLegacyKeys(for: account)
        if makeActive {
            NotificationCenter.default.post(name: .toriiActiveAccountDidChange, object: account)
        }
    }

    @discardableResult
    func switchActiveAccount(to accountId: String) -> StoredAccount? {
        guard let account = accountStore.switchAccount(to: accountId) else {
            return nil
        }
        persistLegacyKeys(for: account)
        NotificationCenter.default.post(name: .toriiActiveAccountDidChange, object: account)
        return account
    }

    @discardableResult
    func migrateLegacyAccountIfNeeded() -> StoredAccount? {
        guard accountStore.accounts.isEmpty else {
            return accountStore.activeAccount
        }
        guard let accountId = secureStore[Keys.accountId],
              let privateKey = secureStore[Keys.privateKey],
              let publicKey = secureStore[Keys.publicKey] else {
            return nil
        }
        let account = StoredAccount(accountId: accountId,
                                    accountAlias: secureStore[Keys.accountAlias],
                                    displayName: secureStore[Keys.displayName],
                                    publicKeyHex: publicKey,
                                    privateKeyHex: privateKey,
                                    recoveryMnemonic: secureStore[Keys.mnemonic],
                                    backupDestinations: legacyBackupDestinations())
        save(account: account, makeActive: true)
        return account
    }

    var accountId: String? {
        get { activeAccount?.accountId }
        set {
            guard let newValue else {
                return
            }
            _ = switchActiveAccount(to: newValue)
        }
    }

    var accountAlias: String? {
        get { activeAccount?.accountAlias }
        set { updateActiveAccount { $0.accountAlias = AccountIdentity.normalizedAlias(newValue) } }
    }

    var privateKeyHex: String? {
        get { activeAccount?.privateKeyHex }
        set {
            guard let newValue else { return }
            updateActiveAccount { $0.privateKeyHex = newValue }
        }
    }

    var publicKeyHex: String? {
        get { activeAccount?.publicKeyHex }
        set {
            guard let newValue else { return }
            updateActiveAccount { $0.publicKeyHex = newValue }
        }
    }

    var displayName: String? {
        get { activeAccount?.displayName }
        set { updateActiveAccount { $0.displayName = newValue } }
    }

    var recoveryMnemonic: String? {
        get { activeAccount?.recoveryMnemonic }
        set { updateActiveAccount { $0.recoveryMnemonic = newValue } }
    }

    var backupDestinations: [KeyBackupDestination] {
        get { activeAccount?.backupDestinations ?? [] }
        set {
            updateActiveAccount { account in
                account.backupDestinations = Array(Set(newValue)).sorted { $0.rawValue < $1.rawValue }
            }
        }
    }

    func clearSession() {
        accountStore.removeAll()
        [Keys.accountId, Keys.accountAlias, Keys.privateKey, Keys.publicKey, Keys.displayName, Keys.mnemonic, Keys.backupDestinations].forEach { key in
            do {
                try secureStore.remove(key)
            } catch {
                // ignore best-effort removal
            }
        }
        NotificationCenter.default.post(name: .toriiActiveAccountDidChange, object: nil)
    }

    private func updateActiveAccount(_ update: (inout StoredAccount) -> Void) {
        guard var account = accountStore.activeAccount else { return }
        update(&account)
        accountStore.save(account: account, makeActive: true)
        persistLegacyKeys(for: account)
    }

    private func persistLegacyKeys(for account: StoredAccount) {
        secureStore[Keys.accountId] = account.accountId
        secureStore[Keys.accountAlias] = account.accountAlias
        secureStore[Keys.privateKey] = account.privateKeyHex
        secureStore[Keys.publicKey] = account.publicKeyHex
        secureStore[Keys.displayName] = account.displayName
        secureStore[Keys.mnemonic] = account.recoveryMnemonic
        let destinations = account.backupDestinations.map { $0.rawValue }.joined(separator: ",")
        secureStore[Keys.backupDestinations] = destinations.isEmpty ? nil : destinations
    }

    private func legacyBackupDestinations() -> [KeyBackupDestination] {
        guard let raw = secureStore[Keys.backupDestinations], !raw.isEmpty else {
            return []
        }
        return raw
            .split(separator: ",")
            .compactMap { KeyBackupDestination(rawValue: String($0)) }
    }
}
