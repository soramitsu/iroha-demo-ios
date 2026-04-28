import UIKit
import TextFieldEffects
import PMAlertController
import Toast_Swift
import IrohaSwift

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
    private var lastSnapshotFailure: Date?
    private lazy var offlineBanner: UIVisualEffectView = makeOfflineBanner()

    private var isVisibleOnScreen: Bool {
        isViewLoaded && view.window != nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        installGlassBackground()
        view.backgroundColor = .clear
        headerback.applyGlassCardStyle(cornerRadius: 24)
        qrImg.applyGlassCardStyle(cornerRadius: 24, includeBlur: false)
        qrImg.clipsToBounds = true
        amountField.delegate = self
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(changeTextField(_:)),
                                               name: UITextField.textDidChangeNotification,
                                               object: amountField)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleAccountChange),
                                               name: .toriiActiveAccountDidChange,
                                               object: nil)
        configureKeyboardAccessory()
        installOfflineBanner()
        accountLabel.isUserInteractionEnabled = true
        accountLabel.delegate = self
        applyGlassStyling()
        navigationController?.topViewController?.navigationItem.title = "Receive"
        updateQR(amount: 0)
        applySoraFonts()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "person.crop.circle"),
                                                           style: .plain,
                                                           target: self,
                                                           action: #selector(showAccountSwitcher))
        tabBarController?.tabBar.isHidden = false
        propertyLabel.text = formattedBalance(DataManager.instance.balance)
        updateAccountFields()
        refreshSnapshot(showLoader: false)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleAccountChange() {
        updateAccountFields()
        propertyLabel.text = formattedBalance(.zero)
        amountField.text = ""
        lastSnapshotFailure = nil
        refreshSnapshot(showLoader: true)
        updateQR(amount: 0)
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
        if let lastFailure = lastSnapshotFailure,
           Date().timeIntervalSince(lastFailure) < 20 {
            return
        }
        hideOfflineBanner()
        var alert: PMAlertController?
        if showLoader, isVisibleOnScreen {
            alert = PMAlertController(title: "通信中", description: "アカウント情報を取得しています", image: nil, style: .alert)
            present(alert!, animated: true)
        }
        Task {
            do {
                let snapshot = try await service.fetchSnapshot(accountId: accountId)
                lastSnapshotFailure = nil
                let balance = service.parseBalance(from: snapshot.balances)
                DataManager.instance.balance = balance
                await MainActor.run {
                    self.propertyLabel.text = self.formattedBalance(balance)
                    alert?.dismiss(animated: true)
                }
            } catch {
                lastSnapshotFailure = Date()
                await MainActor.run {
                    alert?.dismiss(animated: true)
                    if self.isNetworkError(error) {
                        self.showOfflineBanner(message: "オフライン: Toriiに接続できません")
                    } else {
                        self.presentError(message: error.localizedDescription)
                    }
                }
            }
        }
    }

    private func updateAccountFields() {
        accountLabel.text = KeychainManager.instance.activeAccount?.receiveAddressLiteral
            ?? KeychainManager.instance.accountId
        pubkeyLabel.text = KeychainManager.instance.publicKeyHex
    }

    @objc private func changeTextField(_ notification: Notification) {
        guard notification.object as? UITextField === amountField else { return }
        let value = Int(amountField.text ?? "") ?? 0
        updateQR(amount: value)
    }

    private func updateQR(amount: Int) {
        guard let account = KeychainManager.instance.activeAccount?.receiveAddressLiteral
            ?? KeychainManager.instance.accountId else { return }
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
        UIPasteboard.general.string = accountLabel.text?.isEmpty == false
            ? accountLabel.text
            : (KeychainManager.instance.activeAccount?.receiveAddressLiteral ?? KeychainManager.instance.accountId)
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
        let onboarding = SoraNexusOnboardingViewController()
        onboarding.onAccountRegistered = { _ in }
        onboarding.modalPresentationStyle = .fullScreen
        present(onboarding, animated: true)
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

    private func presentError(message: String) {
        guard isVisibleOnScreen else { return }
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

    private func isNetworkError(_ error: Error) -> Bool {
        if let toriiError = error as? ToriiClientError {
            if case let .transport(underlying) = toriiError {
                return isNetworkError(underlying)
            }
            return false
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain { return true }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .timedOut, .networkConnectionLost, .secureConnectionFailed, .dnsLookupFailed, .internationalRoamingOff, .callIsActive, .dataNotAllowed, .resourceUnavailable, .appTransportSecurityRequiresSecureConnection, .backgroundSessionWasDisconnected:
                return true
            default:
                break
            }
        }
        return false
    }

    private func makeOfflineBanner() -> UIVisualEffectView {
        let blur = UIBlurEffect(style: .systemThinMaterialDark)
        let container = UIVisualEffectView(effect: blur)
        container.translatesAutoresizingMaskIntoConstraints = false
        container.alpha = 0
        container.isHidden = true
        container.layer.cornerRadius = 14
        container.layer.masksToBounds = true

        let label = UILabel()
        label.textColor = .white
        label.font = UIFont.sora(.semiBold, size: 13)
        label.numberOfLines = 1
        label.tag = 99
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let icon = UIImageView(image: UIImage(systemName: "wifi.slash"))
        icon.tintColor = .white
        icon.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.contentView.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: container.contentView.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: container.contentView.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: container.contentView.bottomAnchor, constant: -8)
        ])
        return container
    }

    private func installOfflineBanner() {
        view.addSubview(offlineBanner)
        NSLayoutConstraint.activate([
            offlineBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            offlineBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            offlineBanner.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8)
        ])
    }

    private func showOfflineBanner(message: String) {
        guard let label = offlineBanner.viewWithTag(99) as? UILabel else { return }
        label.text = message
        offlineBanner.isHidden = false
        UIView.animate(withDuration: 0.2) {
            self.offlineBanner.alpha = 1
        }
    }

    private func hideOfflineBanner() {
        guard offlineBanner.alpha > 0 else { return }
        UIView.animate(withDuration: 0.2, animations: {
            self.offlineBanner.alpha = 0
        }, completion: { _ in
            self.offlineBanner.isHidden = true
        })
    }
}
