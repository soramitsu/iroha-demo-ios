import UIKit
import TextFieldEffects
import PMAlertController
import Toast_Swift

final class ReceiveViewController: UIViewController, UITextFieldDelegate {
    @IBOutlet private weak var accountLabel: UITextField!
    @IBOutlet private weak var propertyLabel: UILabel!
    @IBOutlet private weak var qrImg: UIImageView!
    @IBOutlet private weak var pubkeyLabel: UITextField!
    @IBOutlet private weak var amountField: HoshiTextField!
    @IBOutlet private weak var headerback: UIView!

    private var qrImage: UIImage?
    private let service = ToriiService.shared
    private let unit = ToriiService.shared.config.unit
    private let colorHex = Bundle.main.infoDictionary?["AppColor"] as? String ?? "E4232D"

    override func viewDidLoad() {
        super.viewDidLoad()
        installGlassBackground()
        headerback.applyGlassCardStyle(cornerRadius: 24)
        qrImg.applyGlassCardStyle(cornerRadius: 24, includeBlur: false)
        qrImg.clipsToBounds = true
        amountField.delegate = self
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(changeTextField(_:)),
                                               name: UITextField.textDidChangeNotification,
                                               object: amountField)
        configureKeyboardAccessory()
        accountLabel.isUserInteractionEnabled = true
        accountLabel.delegate = self
        applyGlassStyling()
        navigationController?.topViewController?.navigationItem.title = "Receive"
        updateQR(amount: 0)
        applySoraFonts()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tabBarController?.tabBar.isHidden = false
        propertyLabel.text = formattedBalance(DataManager.instance.balance)
        updateAccountFields()
        refreshSnapshot(showLoader: false)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func configureKeyboardAccessory() {
        let keyboardHeader = UIToolbar(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 44))
        keyboardHeader.barStyle = .default
        keyboardHeader.sizeToFit()
        let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let done = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(commitButtonTapped))
        keyboardHeader.items = [spacer, done]
        amountField.inputAccessoryView = keyboardHeader
    }

    private func refreshSnapshot(showLoader: Bool) {
        guard let accountId = KeychainManager.instance.accountId else { return }
        var alert: PMAlertController?
        if showLoader {
            alert = PMAlertController(title: "通信中", description: "アカウント情報を取得しています", image: nil, style: .alert)
            present(alert!, animated: true)
        }
        Task {
            do {
                let snapshot = try await service.fetchSnapshot(accountId: accountId)
                let balance = service.parseBalance(from: snapshot.balances)
                DataManager.instance.balance = balance
                await MainActor.run {
                    self.propertyLabel.text = self.formattedBalance(balance)
                    alert?.dismiss(animated: true)
                }
            } catch {
                await MainActor.run {
                    alert?.dismiss(animated: true)
                    self.presentError(message: error.localizedDescription)
                }
            }
        }
    }

    private func updateAccountFields() {
        accountLabel.text = KeychainManager.instance.accountId
        pubkeyLabel.text = KeychainManager.instance.publicKeyHex
    }

    @objc private func changeTextField(_ notification: Notification) {
        guard notification.object as? UITextField === amountField else { return }
        let value = Int(amountField.text ?? "") ?? 0
        updateQR(amount: value)
    }

    private func updateQR(amount: Int) {
        guard let account = KeychainManager.instance.accountId else { return }
        let payload = [
            "account": account,
            "amount": amount,
            "asset": service.config.assetDefinitionId
        ] as [String: Any]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
           let message = String(data: data, encoding: .utf8) {
            qrImage = createQRCode(message: message)
            qrImg.image = qrImage
        }
    }

    @objc private func commitButtonTapped() {
        view.endEditing(true)
    }

    @IBAction private func onCopy(_ sender: Any) {
        UIPasteboard.general.string = accountLabel.text?.isEmpty == false ? accountLabel.text : KeychainManager.instance.accountId
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.impactOccurred()
        var style = ToastStyle()
        style.shadowColor = UIColor.hex(hex: colorHex, alpha: 1)
        style.backgroundColor = UIColor.hex(hex: colorHex, alpha: 1)
        style.messageColor = .white
        if let button = sender as? UIView {
            button.makeToast("コピーしました", duration: 1.0, position: .center, style: style)
        }
    }

    @IBAction private func resetUserData(_ sender: Any) {
        KeychainManager.instance.clearSession()
        DataManager.instance.balance = .zero
        DataManager.instance.transactions = []
        navigateToRegister()
    }

    private func navigateToRegister() {
        let storyboard = storyboard ?? UIStoryboard(name: "Main", bundle: nil)
        if let register = storyboard.instantiateViewController(withIdentifier: "Register") as UIViewController? {
            present(register, animated: true)
        }
    }

    private func presentError(message: String) {
        let alert = PMAlertController(title: "エラー", description: message, image: nil, style: .alert)
        alert.addAction(PMAlertAction(title: "OK", style: .cancel, action: nil))
        present(alert, animated: true)
    }

    private func formattedBalance(_ balance: Decimal) -> String {
        "\(balance.plainString) \(unit)"
    }

    private func applyGlassStyling() {
        [accountLabel, pubkeyLabel].forEach { field in
            field?.applyGlassInputStyle()
            field?.font = UIFont.sora(.medium, size: 14)
            field?.enforceHeight(52)
        }
        amountField.applyGlassInputStyle()
        amountField.font = UIFont.sora(.semiBold, size: 18)
        amountField.enforceHeight(56)
        propertyLabel.textColor = UIColor.glassPrimaryText
        propertyLabel.font = UIFont.sora(.bold, size: 26)
        propertyLabel.numberOfLines = 0
        propertyLabel.adjustsFontForContentSizeCategory = true
        view.tintColor = UIColor.hex(hex: colorHex, alpha: 1)
        headerback.applySoraFontsRecursively()
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if textField === amountField,
           (textField.text?.isEmpty ?? true),
           string == "0" {
            return false
        }
        return true
    }
}
