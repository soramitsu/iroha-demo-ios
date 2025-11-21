import Foundation
import KeychainAccess

enum KeyBackupDestination: String, CaseIterable {
    case manual
    case iCloud
    case googleSecureStorage

    var displayName: String {
        switch self {
        case .manual:
            return "手動バックアップ"
        case .iCloud:
            return "iCloud"
        case .googleSecureStorage:
            return "Google Secure Storage"
        }
    }
}

enum KeyBackupStorageError: Error, LocalizedError {
    case iCloudUnavailable
    case googleStorageFailed

    var errorDescription: String? {
        switch self {
        case .iCloudUnavailable:
            return "iCloudに保存できませんでした。iCloud Driveが有効か確認してください。"
        case .googleStorageFailed:
            return "Google セキュアストレージへの保存に失敗しました。"
        }
    }
}

@MainActor
final class KeyBackupStorage {
    static let shared = KeyBackupStorage()

    private let googleKeychain: Keychain
    private static let iCloudKey = "sora.nexus.mnemonic"
    private static let googleKey = "sora.nexus.mnemonic"

    init(keychain: Keychain = Keychain(service: "jp.co.soramitsu.irohapoint.googlebackup")) {
        self.googleKeychain = keychain
    }

    func store(passphrase: String, destination: KeyBackupDestination) throws {
        guard !passphrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        switch destination {
        case .manual:
            return
        case .iCloud:
            let store = NSUbiquitousKeyValueStore.default
            store.set(passphrase, forKey: Self.iCloudKey)
            guard store.synchronize() else {
                throw KeyBackupStorageError.iCloudUnavailable
            }
        case .googleSecureStorage:
            do {
                try googleKeychain.accessibility(.whenUnlockedThisDeviceOnly).set(passphrase, key: Self.googleKey)
            } catch {
                throw KeyBackupStorageError.googleStorageFailed
            }
        }
    }
}
