import Foundation
import UIKit
import IrohaSwift

struct IrohaConnectPayload {
    let accountId: String
    let accountAlias: String?
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
        self.accountAlias = value(for: "accountAlias") ?? value(for: "alias")
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

@MainActor
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

enum IrohaWalletConnectError: Error, LocalizedError {
    case invalidURL
    case missingParameter(String)
    case invalidSessionId
    case noActiveAccount
    case sessionAlreadyRunning
    case invalidPrivateKey
    case unexpectedControlFrame
    case rejectedByApp(codeID: String, reason: String)
    case noSignRequestReceived

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "IrohaConnectリンクが不正です。"
        case .missingParameter(let name):
            return "IrohaConnectリンクに \(name) がありません。"
        case .invalidSessionId:
            return "IrohaConnectのセッションIDが不正です。"
        case .noActiveAccount:
            return "署名に使用するアカウントがありません。"
        case .sessionAlreadyRunning:
            return "別のIrohaConnect署名が進行中です。"
        case .invalidPrivateKey:
            return "保存済みの秘密鍵を読み込めませんでした。"
        case .unexpectedControlFrame:
            return "IrohaConnectセッションで予期しない制御フレームを受信しました。"
        case .rejectedByApp(let codeID, let reason):
            return "接続元アプリに拒否されました (\(codeID)): \(reason)"
        case .noSignRequestReceived:
            return "署名要求を受信しないままセッションが終了しました。"
        }
    }
}

struct IrohaWalletConnectRequest: Equatable {
    let sidBase64Url: String
    let sessionID: Data
    let token: String
    let chainID: String?
    let baseURL: URL

    init(url: URL) throws {
        guard url.scheme?.lowercased() == "iroha", url.host?.lowercased() == "connect" else {
            throw IrohaWalletConnectError.invalidURL
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw IrohaWalletConnectError.invalidURL
        }
        let queryItems = components.queryItems ?? []

        func value(_ name: String) -> String? {
            queryItems.first { $0.name == name }?.value?.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let sid = value("sid"), !sid.isEmpty else {
            throw IrohaWalletConnectError.missingParameter("sid")
        }
        guard let token = value("token_wallet")
            ?? value("tokenWallet")
            ?? value("token"),
              !token.isEmpty else {
            throw IrohaWalletConnectError.missingParameter("token_wallet")
        }
        guard let decodedSid = Data(base64URLEncoded: sid), decodedSid.count == 32 else {
            throw IrohaWalletConnectError.invalidSessionId
        }

        self.sidBase64Url = sid
        self.sessionID = decodedSid
        self.token = token
        self.chainID = value("chain_id")
        self.baseURL = Self.resolveBaseURL(nodeValue: value("node"))
    }

    private static func resolveBaseURL(nodeValue: String?) -> URL {
        guard let nodeValue, !nodeValue.isEmpty else {
            return defaultToriiBaseURL()
        }

        if let directURL = URL(string: nodeValue), let scheme = directURL.scheme?.lowercased(),
           scheme == "https" || scheme == "http" {
            return directURL
        }

        if let hostURL = URL(string: "https://\(nodeValue)") {
            return hostURL
        }

        return defaultToriiBaseURL()
    }

    private static func defaultToriiBaseURL() -> URL {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "ToriiBaseURL") as? String,
           let url = URL(string: raw) {
            return url
        }
        return URL(string: "https://127.0.0.1:8080")!
    }
}

@MainActor
final class IrohaWalletConnectSessionCoordinator {
    static let shared = IrohaWalletConnectSessionCoordinator()

    private enum Decision {
        case approve
        case reject
    }

    private enum Outcome {
        case signed(domainTag: String?)
        case rejectedByUser
        case closedWithoutSign
    }

    private var task: Task<Void, Never>?

    private init() {}

    @discardableResult
    func handleIncoming(url: URL, presenter: UIViewController?) -> Bool {
        guard url.scheme?.lowercased() == "iroha", url.host?.lowercased() == "connect" else {
            return false
        }

        do {
            let request = try IrohaWalletConnectRequest(url: url)
            guard let account = KeychainManager.instance.activeAccount else {
                throw IrohaWalletConnectError.noActiveAccount
            }
            guard task == nil else {
                throw IrohaWalletConnectError.sessionAlreadyRunning
            }
            presentApprovalPrompt(request: request,
                                  account: account,
                                  presenter: resolvePresenter(from: presenter))
            return true
        } catch {
            notifyFailure(error, sid: nil)
            presentError(error, presenter: resolvePresenter(from: presenter))
            return true
        }
    }

    private func presentApprovalPrompt(request: IrohaWalletConnectRequest,
                                       account: StoredAccount,
                                       presenter: UIViewController?) {
        guard let presenter else {
            notifyFailure(IrohaWalletConnectError.invalidURL, sid: request.sidBase64Url)
            return
        }
        let hostLabel = request.baseURL.host ?? request.baseURL.absoluteString
        let sidPreview = String(request.sidBase64Url.prefix(12))
        let message = [
            "アカウント: \(account.displayTitle)",
            "接続先: \(hostLabel)",
            "セッション: \(sidPreview)..."
        ].joined(separator: "\n")
        let alert = UIAlertController(title: "IrohaConnect署名リクエスト",
                                      message: message,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "拒否", style: .destructive) { [weak self] _ in
            self?.startSession(request: request, account: account, decision: .reject, presenter: presenter)
        })
        alert.addAction(UIAlertAction(title: "承認して署名", style: .default) { [weak self] _ in
            self?.startSession(request: request, account: account, decision: .approve, presenter: presenter)
        })
        presenter.present(alert, animated: true)
    }

    private func startSession(request: IrohaWalletConnectRequest,
                              account: StoredAccount,
                              decision: Decision,
                              presenter: UIViewController) {
        guard task == nil else {
            presentError(IrohaWalletConnectError.sessionAlreadyRunning, presenter: presenter)
            return
        }
        notifyStarted(sid: request.sidBase64Url, accountId: account.accountId)
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let outcome = try await Self.execute(request: request, account: account, decision: decision)
                self.handleOutcome(outcome, sid: request.sidBase64Url, presenter: presenter)
            } catch {
                self.notifyFailure(error, sid: request.sidBase64Url)
                self.presentError(error, presenter: presenter)
            }
            self.task = nil
        }
    }

    private func handleOutcome(_ outcome: Outcome, sid: String, presenter: UIViewController) {
        switch outcome {
        case .signed(let domainTag):
            notifySigned(sid: sid, domainTag: domainTag)
        case .rejectedByUser:
            notifyRejected(sid: sid)
        case .closedWithoutSign:
            notifyFailure(IrohaWalletConnectError.noSignRequestReceived, sid: sid)
            presentError(IrohaWalletConnectError.noSignRequestReceived, presenter: presenter)
        }
    }

    private static func execute(request: IrohaWalletConnectRequest,
                                account: StoredAccount,
                                decision: Decision) async throws -> Outcome {
        let wsRequest = try ConnectClient.makeWebSocketRequest(baseURL: request.baseURL,
                                                               sid: request.sidBase64Url,
                                                               role: .wallet,
                                                               token: request.token)
        let client = ConnectClient(request: wsRequest)
        await client.start()
        defer {
            Task {
                await client.close()
            }
        }

        let session = ConnectSession(sessionID: request.sessionID, client: client)
        let control = try await session.nextControlFrame()
        guard case .open(let open) = control else {
            throw IrohaWalletConnectError.unexpectedControlFrame
        }

        if case .reject = decision {
            let reject = ConnectReject(code: 403,
                                       codeID: "USER_DENIED",
                                       reason: "Rejected by wallet user")
            let frame = ConnectFrame(sessionID: request.sessionID,
                                     direction: .walletToApp,
                                     sequence: 1,
                                     kind: .control(.reject(reject)))
            try await client.send(frame: frame)
            return .rejectedByUser
        }

        guard let accountPrivateKey = Data(hexString: account.privateKeyHex) else {
            throw IrohaWalletConnectError.invalidPrivateKey
        }
        let signingKey = try Keypair(privateKeyBytes: accountPrivateKey)
        let connectKeyPair = try ConnectCrypto.generateKeyPair()
        let preimage = makeApprovePreimage(sessionID: request.sessionID,
                                           appPublicKey: open.appPublicKey,
                                           walletPublicKey: connectKeyPair.publicKey,
                                           accountID: account.accountId)
        let approvalSignature = try signingKey.sign(preimage)
        let approve = ConnectApprove(walletPublicKey: connectKeyPair.publicKey,
                                     accountID: account.accountId,
                                     permissions: nil,
                                     proof: nil,
                                     walletSignature: ConnectWalletSignature(algorithm: "ed25519",
                                                                             signature: approvalSignature),
                                     walletMetadata: ConnectWalletMetadata(name: account.displayTitle,
                                                                          iconURL: nil))
        let approveFrame = ConnectFrame(sessionID: request.sessionID,
                                        direction: .walletToApp,
                                        sequence: 1,
                                        kind: .control(.approve(approve)))
        try await client.send(frame: approveFrame)

        let directionKeys = try ConnectCrypto.deriveDirectionKeys(localPrivateKey: connectKeyPair.privateKey,
                                                                  peerPublicKey: open.appPublicKey,
                                                                  sessionID: request.sessionID)
        session.setDirectionKeys(directionKeys)

        while true {
            let envelope = try await session.nextEnvelope()
            switch envelope.payload {
            case .signRequestRaw(let domainTag, let bytes):
                try await sendSignResult(requestBytes: bytes,
                                         sequence: envelope.sequence,
                                         signingKey: signingKey,
                                         request: request,
                                         encryptionKey: directionKeys.walletToApp,
                                         client: client)
                return .signed(domainTag: domainTag)
            case .signRequestTx(let txBytes):
                try await sendSignResult(requestBytes: txBytes,
                                         sequence: envelope.sequence,
                                         signingKey: signingKey,
                                         request: request,
                                         encryptionKey: directionKeys.walletToApp,
                                         client: client)
                return .signed(domainTag: "SIGN_REQUEST_TX")
            case .controlClose:
                return .closedWithoutSign
            case .controlReject(let reject):
                throw IrohaWalletConnectError.rejectedByApp(codeID: reject.codeID, reason: reject.reason)
            case .displayRequest:
                continue
            case .balanceSnapshot, .signResultOk, .signResultErr:
                continue
            }
        }
    }

    private static func sendSignResult(requestBytes: Data,
                                       sequence: UInt64,
                                       signingKey: Keypair,
                                       request: IrohaWalletConnectRequest,
                                       encryptionKey: Data,
                                       client: ConnectClient) async throws {
        let signature = try signingKey.sign(requestBytes)
        let encryptedFrame = try ConnectEnvelopeCodec.encryptSignResultOk(sequence: sequence,
                                                                          signature: signature,
                                                                          algorithm: "ed25519",
                                                                          key: encryptionKey,
                                                                          sessionID: request.sessionID,
                                                                          direction: .walletToApp)
        try await client.send(data: encryptedFrame)
    }

    nonisolated static func makeApprovePreimage(sessionID: Data,
                                                appPublicKey: Data,
                                                walletPublicKey: Data,
                                                accountID: String) -> Data {
        var preimage = Data("iroha-connect|approve|".utf8)
        preimage.append(sessionID)
        preimage.append(appPublicKey)
        preimage.append(walletPublicKey)
        preimage.append(Data(accountID.utf8))
        return preimage
    }

    private func notifyStarted(sid: String, accountId: String) {
        NotificationCenter.default.post(name: .irohaWalletConnectDidStart,
                                        object: nil,
                                        userInfo: ["sid": sid, "account_id": accountId])
    }

    private func notifyRejected(sid: String) {
        NotificationCenter.default.post(name: .irohaWalletConnectDidReject,
                                        object: nil,
                                        userInfo: ["sid": sid])
    }

    private func notifySigned(sid: String, domainTag: String?) {
        var info: [String: Any] = ["sid": sid]
        if let domainTag {
            info["domain_tag"] = domainTag
        }
        NotificationCenter.default.post(name: .irohaWalletConnectDidSign,
                                        object: nil,
                                        userInfo: info)
    }

    private func notifyFailure(_ error: Error, sid: String?) {
        var info: [String: Any] = ["error": error.localizedDescription]
        if let sid {
            info["sid"] = sid
        }
        NotificationCenter.default.post(name: .irohaWalletConnectDidFail,
                                        object: nil,
                                        userInfo: info)
    }

    private func presentError(_ error: Error, presenter: UIViewController?) {
        guard let presenter else { return }
        let alert = UIAlertController(title: "IrohaConnect",
                                      message: error.localizedDescription,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        presenter.present(alert, animated: true)
    }

    private func resolvePresenter(from presenter: UIViewController?) -> UIViewController? {
        if let presenter {
            return topMostViewController(startingAt: presenter)
        }
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let root = windowScene.windows.first(where: \.isKeyWindow)?.rootViewController else {
            return nil
        }
        return topMostViewController(startingAt: root)
    }

    private func topMostViewController(startingAt viewController: UIViewController) -> UIViewController {
        if let nav = viewController as? UINavigationController,
           let visible = nav.visibleViewController {
            return topMostViewController(startingAt: visible)
        }
        if let tab = viewController as? UITabBarController,
           let selected = tab.selectedViewController {
            return topMostViewController(startingAt: selected)
        }
        if let presented = viewController.presentedViewController {
            return topMostViewController(startingAt: presented)
        }
        return viewController
    }
}

private extension Data {
    init?(base64URLEncoded value: String) {
        var normalized = value.replacingOccurrences(of: "-", with: "+")
        normalized = normalized.replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder != 0 {
            normalized += String(repeating: "=", count: 4 - remainder)
        }
        guard let decoded = Data(base64Encoded: normalized) else {
            return nil
        }
        self = decoded
    }
}
