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

    override func viewDidLoad() {
        super.viewDidLoad()
        installGlassBackground()
        amountField.delegate = self
        configureKeyboardAccessory()
        applyGlassStyling()
        sendButton.addTarget(self, action: #selector(send), for: .touchUpInside)
        applySoraFonts()
        toField.enforceHeight(56)
        amountField.enforceHeight(56)
        sendButton.enforceHeight(56)
        toField.placeholder = "送信先アカウントID"
        amountField.placeholder = "数量 (\(service.config.unit))"

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
            self.sendButton.isEnabled = destinationFilled && validAmount
            self.sendButton.alpha = self.sendButton.isEnabled ? 1.0 : 0.65
        }
        toField.addAction(UIAction { _ in updateSendButtonState() }, for: .editingChanged)
        amountField.addAction(UIAction { _ in updateSendButtonState() }, for: .editingChanged)
        updateSendButtonState()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.topViewController?.navigationItem.title = "Send"
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
            presentError(message: "送信先を入力してください")
            return
        }
        guard destination.caseInsensitiveCompare(KeychainManager.instance.accountId ?? "") != .orderedSame else {
            presentError(message: "自分に送ることはできません")
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
                let status = try await service.submitTransfer(amount: amount, receiverAccountId: destination)
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
