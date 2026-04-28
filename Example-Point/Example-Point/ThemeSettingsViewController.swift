import UIKit

final class ThemeSettingsViewController: UIViewController {
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let segmentedControl = UISegmentedControl(items: ThemeMode.allCases.map { $0.title })
    private let dismissButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        installGlassBackground()
        configureLayout()
        applySoraFonts()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        dismissButton.refreshGlassButtonStyleLayout()
    }

    private func configureLayout() {
        view.tintColor = .iroha
        view.backgroundColor = .clear
        title = "Appearance"

        titleLabel.text = "Appearance"
        titleLabel.font = UIFont.sora(.bold, size: 24)
        titleLabel.textColor = UIColor.glassPrimaryText

        descriptionLabel.text = "Choose how the wallet responds to system dark mode."
        descriptionLabel.numberOfLines = 0
        descriptionLabel.textColor = UIColor.glassSecondaryText

        segmentedControl.selectedSegmentIndex = ThemeManager.shared.mode.rawValue
        segmentedControl.selectedSegmentTintColor = .iroha
        segmentedControl.backgroundColor = UIColor.glassCardBackground(includeBlur: false)
        let normalAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.glassSecondaryText,
            .font: UIFont.sora(.regular, size: 14)
        ]
        let selectedAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.glassPrimaryText,
            .font: UIFont.sora(.semiBold, size: 14)
        ]
        segmentedControl.setTitleTextAttributes(normalAttributes, for: .normal)
        segmentedControl.setTitleTextAttributes(selectedAttributes, for: .selected)
        segmentedControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        segmentedControl.enforceHeight(36)

        dismissButton.setTitle("Done", for: .normal)
        dismissButton.applyGlassButtonStyle()
        dismissButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        dismissButton.enforceHeight(52)

        let stack = UIStackView(arrangedSubviews: [titleLabel, descriptionLabel, segmentedControl, dismissButton])
        stack.axis = .vertical
        stack.spacing = 20
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    @objc private func modeChanged() {
        guard let selected = ThemeMode(rawValue: segmentedControl.selectedSegmentIndex) else { return }
        ThemeManager.shared.mode = selected
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }
}
