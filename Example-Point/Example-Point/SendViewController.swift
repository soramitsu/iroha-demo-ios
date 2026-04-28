import UIKit
import TextFieldEffects
import PMAlertController
import IrohaSwift

final class SendViewController: UIViewController, UITextFieldDelegate {
    @IBOutlet private weak var toField: HoshiTextField!
    @IBOutlet private weak var amountField: HoshiTextField!
    @IBOutlet private weak var sendButton: UIButton!

    private let colorHex = Bundle.main.infoDictionary?["AppColor"] as? String ?? "E4232D"
    private let service = ToriiService.shared
    private var balanceSummaryLabel: UILabel?
    private var availabilityLabel: UILabel?

    override func viewDidLoad() {
        super.viewDidLoad()
        installGlassBackground()
        view.backgroundColor = .clear
        amountField.delegate = self
        configureKeyboardAccessory()
        applyGlassStyling()
        sendButton.addTarget(self, action: #selector(send), for: .touchUpInside)
        applySoraFonts()
        toField.enforceHeight(56)
        amountField.enforceHeight(56)
        sendButton.enforceHeight(56)
        toField.placeholder = "送信先アカウントID / エイリアス"
        amountField.placeholder = "数量 (\(service.config.unit))"
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleAccountChange),
                                               name: .toriiActiveAccountDidChange,
                                               object: nil)

        let summaryCard = UIView()
        summaryCard.translatesAutoresizingMaskIntoConstraints = false
        summaryCard.applyGlassCardStyle(cornerRadius: 22)
        view.addSubview(summaryCard)

        let summaryStack = UIStackView()
        summaryStack.axis = .vertical
        summaryStack.spacing = 8
        summaryStack.translatesAutoresizingMaskIntoConstraints = false
        summaryStack.isLayoutMarginsRelativeArrangement = true
        summaryStack.layoutMargins = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        summaryCard.addSubview(summaryStack)

        let summaryTitle = UILabel()
        summaryTitle.text = "Available"
        summaryTitle.font = UIFont.sora(.semiBold, size: 13)
        summaryTitle.textColor = UIColor.glassSecondaryText

        let balanceLabel = UILabel()
        balanceLabel.font = UIFont.sora(.bold, size: 28)
        balanceLabel.textColor = UIColor.glassPrimaryText
        balanceLabel.adjustsFontForContentSizeCategory = true
        balanceLabel.text = "\(DataManager.instance.balance.plainString) \(service.config.unit)"
        balanceSummaryLabel = balanceLabel

        let networkLabel = UILabel()
        networkLabel.textColor = UIColor.glassSecondaryText
        networkLabel.font = UIFont.sora(.medium, size: 13)
        networkLabel.text = "Network: \(service.config.chainId)"

        summaryStack.addArrangedSubview(summaryTitle)
        summaryStack.addArrangedSubview(balanceLabel)
        summaryStack.addArrangedSubview(networkLabel)

        let availabilityLabel = UILabel()
        availabilityLabel.font = UIFont.sora(.medium, size: 13)
        availabilityLabel.textColor = .systemRed
        availabilityLabel.numberOfLines = 0
        availabilityLabel.textAlignment = .left
        availabilityLabel.text = "ネイティブ署名ライブラリが見つかりません。送金機能は現在利用できません。"
        availabilityLabel.isHidden = service.canSubmitTransactions
        availabilityLabel.translatesAutoresizingMaskIntoConstraints = false
        summaryStack.addArrangedSubview(availabilityLabel)
        self.availabilityLabel = availabilityLabel

        NSLayoutConstraint.activate([
            summaryCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            summaryCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            summaryCard.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),

            summaryStack.leadingAnchor.constraint(equalTo: summaryCard.leadingAnchor),
            summaryStack.trailingAnchor.constraint(equalTo: summaryCard.trailingAnchor),
            summaryStack.topAnchor.constraint(equalTo: summaryCard.topAnchor),
            summaryStack.bottomAnchor.constraint(equalTo: summaryCard.bottomAnchor)
        ])

        let updateSendButtonState: () -> Void = { [weak self] in
            guard let self else { return }
            let destinationFilled = !(self.toField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            let amount = Decimal(string: self.amountField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? .zero
            let validAmount = amount > 0
            let available = self.service.canSubmitTransactions
            self.sendButton.isEnabled = destinationFilled && validAmount && available
            self.sendButton.alpha = self.sendButton.isEnabled ? 1.0 : 0.65
            self.availabilityLabel?.isHidden = available
        }
        toField.addAction(UIAction { _ in updateSendButtonState() }, for: .editingChanged)
        amountField.addAction(UIAction { _ in updateSendButtonState() }, for: .editingChanged)
        updateSendButtonState()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.topViewController?.navigationItem.title = "Send"
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "person.crop.circle"),
                                                           style: .plain,
                                                           target: self,
                                                           action: #selector(showAccountSwitcher))
        tabBarController?.tabBar.isHidden = false
        balanceSummaryLabel?.text = "\(DataManager.instance.balance.plainString) \(service.config.unit)"
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        sendButton.refreshGlassButtonStyleLayout()
    }

    private func configureKeyboardAccessory() {
        let toolbar = UIToolbar(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 44))
        toolbar.barStyle = .default
        toolbar.sizeToFit()
        let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let done = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(commitButtonTapped))
        toolbar.items = [spacer, done]
        toField.inputAccessoryView = toolbar
        amountField.inputAccessoryView = toolbar
    }

    private func applyGlassStyling() {
        [toField, amountField].forEach { field in
            field?.applyGlassInputStyle()
        }
        sendButton.applyGlassButtonStyle(accent: UIColor.hex(hex: colorHex, alpha: 1))
        sendButton.titleLabel?.adjustsFontForContentSizeCategory = true
    }

    @objc private func commitButtonTapped() {
        view.endEditing(true)
    }

    @objc private func send() {
        guard let destination = toField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !destination.isEmpty else {
            presentError(message: "送信先のアカウントIDまたはエイリアスを入力してください")
            return
        }
        guard let amountText = amountField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              let amount = Decimal(string: amountText), amount > 0 else {
            presentError(message: "送信量を入力してください")
            return
        }

        let progress = PMAlertController(title: "送信中", description: "IRHを送信しています", image: nil, style: .alert)
        present(progress, animated: true)

        Task {
            do {
                let resolvedReceiver = try await service.resolveAccountReference(destination)
                if let currentAccountId = KeychainManager.instance.accountId,
                   resolvedReceiver.accountId == currentAccountId {
                    await MainActor.run {
                        progress.dismiss(animated: true) {
                            self.presentError(message: "自分に送ることはできません")
                        }
                    }
                    return
                }
                let status = try await service.submitTransfer(amount: amount,
                                                              receiverAccountId: resolvedReceiver.accountId)
                NotificationCenter.default.post(name: .toriiWalletShouldRefresh, object: nil)
                await MainActor.run {
                    progress.dismiss(animated: true) {
                        self.presentSuccess(status: status)
                    }
                }
            } catch {
                await MainActor.run {
                    progress.dismiss(animated: true) {
                        self.presentError(message: error.localizedDescription)
                    }
                }
            }
        }
    }

    private func presentSuccess(status: ToriiPipelineTransactionStatus) {
        let alert = PMAlertController(title: "完了",
                                      description: "送金が完了しました (\(status.content.status.kind))",
                                      image: nil,
                                      style: .alert)
        alert.addAction(PMAlertAction(title: "OK", style: .default) { [weak self] in
            self?.toField.text = ""
            self?.amountField.text = ""
            self?.sendButton.isEnabled = false
            self?.sendButton.alpha = 0.65
        })
        present(alert, animated: true)
    }

    private func presentError(message: String) {
        let alert = PMAlertController(title: "エラー", description: message, image: nil, style: .alert)
        alert.addAction(PMAlertAction(title: "OK", style: .cancel, action: nil))
        present(alert, animated: true)
    }

    @objc private func handleAccountChange() {
        balanceSummaryLabel?.text = "\(DataManager.instance.balance.plainString) \(service.config.unit)"
        toField.text = ""
        amountField.text = ""
        sendButton.isEnabled = false
        sendButton.alpha = 0.65
    }

    @objc private func showAccountSwitcher() {
        let controller = AccountSwitcherViewController()
        controller.onAddAccount = { [weak self] in
            self?.presentAdditionalRegistration()
        }
        controller.modalPresentationStyle = .pageSheet
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(controller, animated: true)
    }

    private func presentAdditionalRegistration() {
        let onboarding = SoraNexusOnboardingViewController()
        onboarding.onAccountRegistered = { _ in }
        onboarding.modalPresentationStyle = .fullScreen
        present(onboarding, animated: true)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if textField === amountField,
           (textField.text?.isEmpty ?? true),
           string == "0" {
            return false
        }
        return true
    }

    func prefill(receiver: String, amount: String?) {
        loadViewIfNeeded()
        toField.text = receiver
        amountField.text = amount
        toField.sendActions(for: .editingChanged)
        amountField.sendActions(for: .editingChanged)
    }
}
