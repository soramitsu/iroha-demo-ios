import Foundation

extension KeychainManager {
    private enum Keys {
        static let accountId = "torii.accountId"
        static let privateKey = "torii.privateKey"
        static let publicKey = "torii.publicKey"
        static let displayName = "torii.displayName"
        static let mnemonic = "torii.mnemonic"
        static let backupDestinations = "torii.backupDestinations"
    }

    var accountId: String? {
        get { keychain[Keys.accountId] }
        set { keychain[Keys.accountId] = newValue }
    }

    var privateKeyHex: String? {
        get { keychain[Keys.privateKey] }
        set { keychain[Keys.privateKey] = newValue }
    }

    var publicKeyHex: String? {
        get { keychain[Keys.publicKey] }
        set { keychain[Keys.publicKey] = newValue }
    }

    var displayName: String? {
        get { keychain[Keys.displayName] }
        set { keychain[Keys.displayName] = newValue }
    }

    var recoveryMnemonic: String? {
        get { keychain[Keys.mnemonic] }
        set { keychain[Keys.mnemonic] = newValue }
    }

    var backupDestinations: [KeyBackupDestination] {
        get {
            guard let raw = keychain[Keys.backupDestinations], !raw.isEmpty else {
                return []
            }
            return raw
                .split(separator: ",")
                .compactMap { KeyBackupDestination(rawValue: String($0)) }
        }
        set {
            if newValue.isEmpty {
                keychain[Keys.backupDestinations] = nil
            } else {
                let deduplicated = Array(Set(newValue)).sorted { $0.rawValue < $1.rawValue }
                let raw = deduplicated.map { $0.rawValue }.joined(separator: ",")
                keychain[Keys.backupDestinations] = raw
            }
        }
    }

    func clearSession() {
        [Keys.accountId, Keys.privateKey, Keys.publicKey, Keys.displayName, Keys.mnemonic, Keys.backupDestinations].forEach { key in
            do {
                try keychain.remove(key)
            } catch {
                // ignore best-effort removal
            }
        }
    }
}
