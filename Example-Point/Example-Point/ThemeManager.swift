import UIKit

extension Notification.Name {
    static let themeDidChange = Notification.Name("ThemeManagerThemeDidChange")
}

enum ThemeMode: Int, CaseIterable {
    case system
    case light
    case dark

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }
}

final class ThemeManager {
    static let shared = ThemeManager()

    private let storageKey = "ThemeManager.mode"
    private let defaults = UserDefaults.standard

    private init() {
        if let stored = ThemeMode(rawValue: defaults.integer(forKey: storageKey)) {
            mode = stored
        } else {
            mode = .system
        }
    }

    var mode: ThemeMode {
        didSet {
            defaults.set(mode.rawValue, forKey: storageKey)
            NotificationCenter.default.post(name: .themeDidChange, object: mode)
        }
    }

    func apply(to window: UIWindow?) {
        window?.overrideUserInterfaceStyle = mode.interfaceStyle
    }
}
