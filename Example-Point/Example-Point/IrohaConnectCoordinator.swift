import Foundation
import UIKit

struct IrohaConnectPayload {
    let accountId: String
    let publicKeyHex: String
    let privateKeyHex: String
    let displayName: String?

    init(url: URL) throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw IrohaConnectError.invalidResponse
        }
        let items = components.queryItems ?? []
        func value(for key: String) -> String? {
            items.first { $0.name == key }?.value
        }
        guard let accountId = value(for: "accountId"), !accountId.isEmpty else {
            throw IrohaConnectError.missingField("accountId")
        }
        guard let publicKey = value(for: "publicKey"), !publicKey.isEmpty else {
            throw IrohaConnectError.missingField("publicKey")
        }
        guard let privateKey = value(for: "privateKey"), !privateKey.isEmpty else {
            throw IrohaConnectError.missingField("privateKey")
        }
        self.accountId = accountId
        self.publicKeyHex = publicKey
        self.privateKeyHex = privateKey
        self.displayName = value(for: "displayName")
    }
}

enum IrohaConnectError: Error, LocalizedError {
    case appUnavailable
    case invalidResponse
    case missingField(String)
    case unsupportedURL

    var errorDescription: String? {
        switch self {
        case .appUnavailable:
            return "IrohaConnectアプリを開けませんでした。"
        case .invalidResponse:
            return "IrohaConnectからの応答が不正です。"
        case .missingField(let field):
            return "IrohaConnectから \(field) が届きませんでした。"
        case .unsupportedURL:
            return "サポートされていないURLです。"
        }
    }
}

protocol IrohaConnectCoordinatorDelegate: AnyObject {
    func irohaConnectCoordinator(_ coordinator: IrohaConnectCoordinator, didReceive payload: IrohaConnectPayload)
    func irohaConnectCoordinator(_ coordinator: IrohaConnectCoordinator, didFail error: IrohaConnectError)
}

final class IrohaConnectCoordinator {
    static let shared = IrohaConnectCoordinator()

    weak var delegate: IrohaConnectCoordinatorDelegate? {
        didSet { deliverPendingEvents() }
    }

    private let callbackScheme = "example-point"
    private let callbackHost = "irohaconnect"
    private var pendingPayload: IrohaConnectPayload?
    private var pendingError: IrohaConnectError?

    private init() {}

    func beginConnection() {
        guard let callbackURL = makeCallbackURL() else {
            delegate?.irohaConnectCoordinator(self, didFail: .unsupportedURL)
            return
        }
        guard let url = URL(string: "irohaconnect://connect?callback=\(callbackURL.absoluteString)") else {
            delegate?.irohaConnectCoordinator(self, didFail: .unsupportedURL)
            return
        }
        UIApplication.shared.open(url, options: [:]) { [weak self] success in
            guard let self else { return }
            if !success {
                self.delegate?.irohaConnectCoordinator(self, didFail: .appUnavailable)
            }
        }
    }

    func handleCallback(url: URL) -> Bool {
        guard canHandle(url) else { return false }
        do {
            let payload = try IrohaConnectPayload(url: url)
            if let delegate {
                delegate.irohaConnectCoordinator(self, didReceive: payload)
            } else {
                pendingPayload = payload
            }
        } catch let error as IrohaConnectError {
            if let delegate {
                delegate.irohaConnectCoordinator(self, didFail: error)
            } else {
                pendingError = error
            }
        } catch {
            if let delegate {
                delegate.irohaConnectCoordinator(self, didFail: .invalidResponse)
            } else {
                pendingError = .invalidResponse
            }
        }
        return true
    }

    private func makeCallbackURL() -> URL? {
        var components = URLComponents()
        components.scheme = callbackScheme
        components.host = callbackHost
        return components.url
    }

    private func canHandle(_ url: URL) -> Bool {
        url.scheme == callbackScheme && url.host == callbackHost
    }

    private func deliverPendingEvents() {
        if let payload = pendingPayload {
            delegate?.irohaConnectCoordinator(self, didReceive: payload)
            pendingPayload = nil
        }
        if let error = pendingError {
            delegate?.irohaConnectCoordinator(self, didFail: error)
            pendingError = nil
        }
    }
}
