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
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.topViewController?.navigationItem.title = "Send"
        tabBarController?.tabBar.isHidden = false
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
    }
}
