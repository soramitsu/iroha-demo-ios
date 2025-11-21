import UIKit

@MainActor
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var themeObserver: NSObjectProtocol?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = makeRootViewController()
        window.tintColor = .iroha
        self.window = window
        ThemeManager.shared.apply(to: window)
        themeObserver = NotificationCenter.default.addObserver(forName: .themeDidChange,
                                                               object: nil,
                                                               queue: .main) { [weak self] _ in
            ThemeManager.shared.apply(to: self?.window)
        }
        window.makeKeyAndVisible()
    }

    private func makeRootViewController() -> UIViewController {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        if KeychainManager.instance.privateKeyHex != nil,
           let contents = storyboard.instantiateViewController(withIdentifier: "Contents") as UIViewController? {
            return contents
        }
        return SoraNexusOnboardingViewController()
    }

    func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
        guard let url = contexts.first?.url else { return }
        _ = IrohaConnectCoordinator.shared.handleCallback(url: url)
    }

    @MainActor
    deinit {
        if let observer = themeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
