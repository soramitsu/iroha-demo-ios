import UIKit

@MainActor
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = makeRootViewController()
        window.tintColor = .iroha
        self.window = window
        ThemeManager.shared.apply(to: window)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleThemeDidChange),
                                               name: .themeDidChange,
                                               object: nil)
        window.makeKeyAndVisible()
    }

    private func makeRootViewController() -> UIViewController {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        _ = KeychainManager.instance.migrateLegacyAccountIfNeeded()
        if KeychainManager.instance.activeAccount != nil,
           let contents = storyboard.instantiateViewController(withIdentifier: "Contents") as UIViewController? {
            SubscriptionHubConfigurator.configureIfNeeded(contents)
            return contents
        }
        return SoraNexusOnboardingViewController()
    }

    func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
        guard let url = contexts.first?.url else { return }
        if IrohaWalletConnectSessionCoordinator.shared.handleIncoming(url: url, presenter: window?.rootViewController) {
            return
        }
        _ = IrohaConnectCoordinator.shared.handleCallback(url: url)
    }

    @objc
    private func handleThemeDidChange() {
        ThemeManager.shared.apply(to: window)
    }

    @MainActor
    deinit {
        NotificationCenter.default.removeObserver(self, name: .themeDidChange, object: nil)
    }
}
