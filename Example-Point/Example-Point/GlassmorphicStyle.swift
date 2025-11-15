import UIKit
import ObjectiveC
import TextFieldEffects

/// Full-screen gradient background that respects device bounds.
final class GradientBackgroundView: UIView {
    private var traitRegistration: UITraitChangeRegistration?

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        false
    }

    override class var layerClass: AnyClass {
        CAGradientLayer.self
    }

    private var gradientLayer: CAGradientLayer {
        // swiftlint:disable:next force_cast
        return layer as! CAGradientLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        isUserInteractionEnabled = false
        gradientLayer.locations = [0, 0.65, 1]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        updateColors()
        if #available(iOS 17.0, *) {
            traitRegistration = registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: GradientBackgroundView, previous: UITraitCollection) in
                guard previous.userInterfaceStyle != view.traitCollection.userInterfaceStyle else { return }
                view.updateColors()
            }
        }
    }

    @available(iOS, deprecated: 17.0)
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard #unavailable(iOS 17.0) else { return }
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
        updateColors()
    }

    private func updateColors() {
        let isDark = traitCollection.userInterfaceStyle == .dark
        let top = isDark ? UIColor(red: 0.06, green: 0.0, blue: 0.12, alpha: 1) : UIColor(red: 1, green: 0.92, blue: 0.95, alpha: 1)
        let middle = isDark ? UIColor(red: 0.16, green: 0.03, blue: 0.2, alpha: 1) : UIColor(red: 1, green: 0.97, blue: 0.98, alpha: 1)
        let bottom = isDark ? UIColor.black.withAlphaComponent(0.9) : UIColor(red: 0.87, green: 0.93, blue: 1, alpha: 1)
        gradientLayer.colors = [top.cgColor, middle.cgColor, bottom.cgColor]
    }
}

/// Visual effect view used purely for decoration; forwards every touch to underlying content.
private final class DecorativeBlurView: UIVisualEffectView {
    override init(effect: UIVisualEffect?) {
        super.init(effect: effect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        isUserInteractionEnabled = false
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        false
    }
}

private let glassBlurTag = 9_812_334
private var associatedSakuraKey: UInt8 = 0

extension UIView {
    func applyGlassCardStyle(cornerRadius: CGFloat = 24, includeBlur: Bool = true) {
        if includeBlur && viewWithTag(glassBlurTag) == nil {
            let blur = DecorativeBlurView(effect: UIBlurEffect(style: .systemUltraThinMaterialLight))
            blur.translatesAutoresizingMaskIntoConstraints = false
            blur.layer.cornerRadius = cornerRadius
            blur.clipsToBounds = true
            blur.tag = glassBlurTag
            insertSubview(blur, at: 0)
            blur.pinEdges(to: self)
        }

        backgroundColor = UIColor.glassCardBackground(includeBlur: includeBlur)
        layer.cornerRadius = cornerRadius
        layer.borderColor = UIColor.glassCardBorder.cgColor
        layer.borderWidth = 1
        layer.shadowColor = UIColor.glassShadow.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 18
        layer.shadowOffset = CGSize(width: 0, height: 12)
    }

    func pinEdges(to other: UIView) {
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: other.leadingAnchor),
            trailingAnchor.constraint(equalTo: other.trailingAnchor),
            topAnchor.constraint(equalTo: other.topAnchor),
            bottomAnchor.constraint(equalTo: other.bottomAnchor)
        ])
    }

    func enforceHeight(_ height: CGFloat) {
        let constraint = heightAnchor.constraint(equalToConstant: height)
        constraint.priority = .required
        constraint.isActive = true
    }
}

extension UITextField {
    func applyGlassInputStyle() {
        textColor = UIColor.glassPrimaryText
        tintColor = UIColor.iroha
        backgroundColor = UIColor.glassFieldBackground
        layer.cornerRadius = 18
        layer.masksToBounds = true
        if let hoshi = self as? HoshiTextField {
            hoshi.borderInactiveColor = UIColor.dynamicGlassStroke
            hoshi.borderActiveColor = UIColor.iroha
            hoshi.placeholderColor = UIColor.glassPlaceholderText
            hoshi.backgroundColor = UIColor.clear
        } else if let placeholder = placeholder {
            attributedPlaceholder = NSAttributedString(string: placeholder,
                                                       attributes: [.foregroundColor: UIColor.glassPlaceholderText])
        }
        keyboardAppearance = traitCollection.userInterfaceStyle == .dark ? .dark : .light
    }
}

private var gradientAssociationKey: UInt8 = 0

extension UIButton {
    private var glassGradientLayer: CAGradientLayer? {
        get { objc_getAssociatedObject(self, &gradientAssociationKey) as? CAGradientLayer }
        set { objc_setAssociatedObject(self, &gradientAssociationKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    func applyGlassButtonStyle(accent: UIColor = .iroha) {
        layer.cornerRadius = 20
        layer.masksToBounds = false
        layer.shadowColor = UIColor.glassShadow.cgColor
        layer.shadowOpacity = 0.4
        layer.shadowOffset = CGSize(width: 0, height: 8)
        layer.shadowRadius = 14
        setTitleColor(.white, for: .normal)
        setTitleColor(UIColor.white.withAlphaComponent(0.6), for: .highlighted)

        let gradient = glassGradientLayer ?? CAGradientLayer()
        let start = UIColor { trait in
            trait.userInterfaceStyle == .dark ? accent.withAlphaComponent(0.9) : accent.withAlphaComponent(0.9)
        }
        let end = UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.15) : accent.withAlphaComponent(0.6)
        }
        gradient.colors = [start.cgColor, end.cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        gradient.frame = bounds
        gradient.cornerRadius = layer.cornerRadius
        gradient.name = "glass.button.gradient"
        gradient.allowsGroupOpacity = true
        gradient.removeFromSuperlayer()
        layer.insertSublayer(gradient, at: 0)
        glassGradientLayer = gradient
    }

    func refreshGlassButtonStyleLayout() {
        glassGradientLayer?.frame = bounds
        glassGradientLayer?.cornerRadius = layer.cornerRadius
    }
}

extension UIViewController {
    func installGlassBackground() {
        removeGlassBackground()
        let background = GradientBackgroundView(frame: view.bounds)
        background.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(background, at: 0)
        background.pinEdges(to: view)

        let sakura = SakuraEmitterView(frame: view.bounds)
        sakura.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(sakura, aboveSubview: background)
        sakura.pinEdges(to: view)
        objc_setAssociatedObject(self, &associatedSakuraKey, sakura, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    func removeGlassBackground() {
        view.subviews
            .compactMap { $0 as? GradientBackgroundView }
            .forEach { $0.removeFromSuperview() }
        if let sakura = objc_getAssociatedObject(self, &associatedSakuraKey) as? SakuraEmitterView {
            sakura.removeFromSuperview()
            objc_setAssociatedObject(self, &associatedSakuraKey, nil, .OBJC_ASSOCIATION_ASSIGN)
        }
    }
}

extension UIColor {
    static func glassCardBackground(includeBlur: Bool) -> UIColor {
        UIColor { trait in
            if trait.userInterfaceStyle == .dark {
                return includeBlur ? UIColor.white.withAlphaComponent(0.08) : UIColor.white.withAlphaComponent(0.05)
            } else {
                return includeBlur ? UIColor(white: 1.0, alpha: 0.85) : UIColor(white: 1.0, alpha: 0.7)
            }
        }
    }

    static var glassCardBorder: UIColor {
        UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.25) : UIColor.black.withAlphaComponent(0.05)
        }
    }

    static var glassShadow: UIColor {
        UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor.black.withAlphaComponent(0.4) : UIColor.black.withAlphaComponent(0.2)
        }
    }

    static var glassFieldBackground: UIColor {
        UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.08) : UIColor.white.withAlphaComponent(0.9)
        }
    }

    static var dynamicGlassStroke: UIColor {
        UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.35) : UIColor.black.withAlphaComponent(0.2)
        }
    }

    static var dynamicPlaceholder: UIColor {
        UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor.white.withAlphaComponent(0.45) : UIColor.black.withAlphaComponent(0.35)
        }
    }

    static var glassPrimaryText: UIColor {
        UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(white: 0.98, alpha: 1.0)
                : UIColor(red: 22/255, green: 28/255, blue: 41/255, alpha: 1.0)
        }
    }

    static var glassSecondaryText: UIColor {
        UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(white: 0.9, alpha: 0.75)
                : UIColor(red: 64/255, green: 72/255, blue: 90/255, alpha: 0.85)
        }
    }

    static var glassPlaceholderText: UIColor {
        UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.45)
                : UIColor.black.withAlphaComponent(0.35)
        }
    }
}
