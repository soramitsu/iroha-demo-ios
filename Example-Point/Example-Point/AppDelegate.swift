import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        configureAppearance()
        return true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    private func configureAppearance() {
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithTransparentBackground()
        navAppearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
        let titleFont = UIFont.sora(.semiBold, size: 18)
        let largeFont = UIFont.sora(.bold, size: 32)
        navAppearance.titleTextAttributes = [
            .foregroundColor: UIColor.label,
            .font: titleFont
        ]
        navAppearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor.label,
            .font: largeFont
        ]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
        UINavigationBar.appearance().tintColor = UIColor.label
        let barButtonAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: UIColor.label
        ]
        UIBarButtonItem.appearance().setTitleTextAttributes(barButtonAttributes, for: .normal)
        UIBarButtonItem.appearance().setTitleTextAttributes(barButtonAttributes, for: .highlighted)

        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithTransparentBackground()
        tabAppearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
        tabAppearance.stackedLayoutAppearance.selected.iconColor = .iroha
        tabAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [
            .foregroundColor: UIColor.iroha,
            .font: UIFont.sora(.medium, size: 12)
        ]
        tabAppearance.stackedLayoutAppearance.normal.iconColor = UIColor.secondaryLabel
        tabAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor.secondaryLabel,
            .font: UIFont.sora(.regular, size: 12)
        ]
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
    }
}
