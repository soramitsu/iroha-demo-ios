import UIKit

enum SoraFontWeight: CaseIterable {
    case thin
    case extraLight
    case light
    case regular
    case medium
    case semiBold
    case bold
    case extraBold

    fileprivate func fontName(italic: Bool) -> String {
        switch (self, italic) {
        case (.thin, false): return "Sora-Thin"
        case (.thin, true): return "Sora-ThinItalic"
        case (.extraLight, false): return "Sora-ExtraLight"
        case (.extraLight, true): return "Sora-ExtraLightItalic"
        case (.light, false): return "Sora-Light"
        case (.light, true): return "Sora-LightItalic"
        case (.regular, false): return "Sora-Regular"
        case (.regular, true): return "Sora-Italic"
        case (.medium, false): return "Sora-Medium"
        case (.medium, true): return "Sora-MediumItalic"
        case (.semiBold, false): return "Sora-SemiBold"
        case (.semiBold, true): return "Sora-SemiBoldItalic"
        case (.bold, false): return "Sora-Bold"
        case (.bold, true): return "Sora-BoldItalic"
        case (.extraBold, false): return "Sora-ExtraBold"
        case (.extraBold, true): return "Sora-ExtraBoldItalic"
        }
    }

    fileprivate static func from(systemWeight: UIFont.Weight) -> SoraFontWeight {
        let value = systemWeight.rawValue
        if value <= UIFont.Weight.ultraLight.rawValue {
            return .thin
        } else if value <= UIFont.Weight.light.rawValue - 0.1 {
            return .extraLight
        } else if value < UIFont.Weight.regular.rawValue {
            return .light
        } else if value < UIFont.Weight.medium.rawValue {
            return .regular
        } else if value < UIFont.Weight.semibold.rawValue {
            return .medium
        } else if value < UIFont.Weight.bold.rawValue {
            return .semiBold
        } else if value < UIFont.Weight.heavy.rawValue {
            return .bold
        } else {
            return .extraBold
        }
    }

    fileprivate var fallbackWeight: UIFont.Weight {
        switch self {
        case .thin: return .thin
        case .extraLight: return .ultraLight
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semiBold: return .semibold
        case .bold: return .bold
        case .extraBold: return .heavy
        }
    }
}

extension UIFont {
    static func sora(_ weight: SoraFontWeight, size: CGFloat, italic: Bool = false) -> UIFont {
        let fontName = weight.fontName(italic: italic)
        if let font = UIFont(name: fontName, size: size) {
            return font
        }
        return UIFont.systemFont(ofSize: size, weight: weight.fallbackWeight)
    }

    fileprivate func soraAdjusted() -> UIFont {
        let traits = fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any]
        let weightValue = (traits?[.weight] as? CGFloat) ?? UIFont.Weight.regular.rawValue
        let isItalic = fontDescriptor.symbolicTraits.contains(.traitItalic)
        let soraWeight = SoraFontWeight.from(systemWeight: UIFont.Weight(rawValue: weightValue))
        return UIFont.sora(soraWeight, size: pointSize, italic: isItalic)
    }
}

extension UIView {
    func applySoraFontsRecursively() {
        if let label = self as? UILabel {
            label.font = label.font?.soraAdjusted()
        } else if let textField = self as? UITextField, let font = textField.font {
            textField.font = font.soraAdjusted()
        } else if let textView = self as? UITextView, let font = textView.font {
            textView.font = font.soraAdjusted()
        } else if let button = self as? UIButton, let font = button.titleLabel?.font {
            button.titleLabel?.font = font.soraAdjusted()
        }
        subviews.forEach { $0.applySoraFontsRecursively() }
    }
}

extension UIViewController {
    func applySoraFonts() {
        view.applySoraFontsRecursively()
    }
}
