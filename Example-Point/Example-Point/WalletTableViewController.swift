import UIKit
import PMAlertController
import IrohaSwift
import CryptoKit
import AVFoundation
#if canImport(CoreNFC) && !targetEnvironment(simulator)
import CoreNFC
#endif

// MARK: - QR Scanner

@MainActor
protocol OfflineVoucherScannerDelegate: AnyObject {
    func scanner(_ scanner: OfflineVoucherScannerViewController, didScan payload: String)
    func scannerDidCancel(_ scanner: OfflineVoucherScannerViewController)
}

@MainActor
final class OfflineVoucherScannerViewController: UIViewController, @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
    weak var delegate: OfflineVoucherScannerDelegate?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let statusLabel = UILabel()
    private let closeButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureOverlay()
        configureSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }

    private func configureOverlay() {
        statusLabel.text = "QRコードを枠内にかざしてください"
        statusLabel.textColor = .white
        statusLabel.font = UIFont.sora(.semiBold, size: 16)
        statusLabel.textAlignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .white
        closeButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            session.stopRunning()
            delegate?.scannerDidCancel(self)
            dismiss(animated: true)
        }, for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(statusLabel)
        view.addSubview(closeButton)
        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16)
        ])
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            statusLabel.text = "カメラにアクセスできません。"
            return
        }
        let output = AVCaptureMetadataOutput()
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }
        output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.layer.bounds
        view.layer.insertSublayer(preview, at: 0)
        previewLayer = preview

        session.startRunning()
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue else { return }
        session.stopRunning()
        delegate?.scanner(self, didScan: value)
        dismiss(animated: true)
    }
}

extension OfflinePaymentsViewController: OfflineVoucherScannerDelegate {
    func scanner(_ scanner: OfflineVoucherScannerViewController, didScan payload: String) {
        voucherPayloadView.text = payload
        handleImportedPayload(payload)
    }

    func scannerDidCancel(_ scanner: OfflineVoucherScannerViewController) {
        // No-op
    }
}

final class WalletTableViewController: UITableViewController {
    private enum Section {
        case main
    }

    private struct TransactionItem: Hashable {
        let transaction: ToriiTxItem
        private let identifier: String

        init(transaction: ToriiTxItem) {
            self.transaction = transaction
            let authority = transaction.authority ?? "unknown"
            let timestamp = transaction.timestamp_ms.map(String.init) ?? "0"
            identifier = "\(transaction.entrypoint_hash)|\(timestamp)|\(authority)|\(transaction.result_ok)"
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(identifier)
        }

        static func == (lhs: TransactionItem, rhs: TransactionItem) -> Bool {
            lhs.identifier == rhs.identifier
        }
    }

    private let historyRefresh = UIRefreshControl()
    private var dataSource: UITableViewDiffableDataSource<Section, TransactionItem>!
    private let config = ToriiService.shared.config
    private var balanceLabel: UILabel?
    private let colorHex = Bundle.main.infoDictionary?["AppColor"] as? String ?? "E4232D"
    private lazy var offlineBanner: UIVisualEffectView = makeOfflineBanner()
    private var lastSnapshotFailure: Date?

    private var isVisibleOnScreen: Bool {
        isViewLoaded && view.window != nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.backgroundColor = .clear
        tableView.backgroundView = GradientBackgroundView(frame: view.bounds)
        tableView.sectionHeaderHeight = UITableView.automaticDimension
        tableView.estimatedSectionHeaderHeight = 160
        tableView.contentInset = UIEdgeInsets(top: 16, left: 0, bottom: 32, right: 0)
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false
        tableView.register(TransactionCell.self, forCellReuseIdentifier: "TransactionCell")
        configureDataSource()

        historyRefresh.addTarget(self, action: #selector(refreshTriggered), for: .valueChanged)
        historyRefresh.tintColor = UIColor.iroha
        tableView.refreshControl = historyRefresh

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleWalletRefreshNotification),
                                               name: .toriiWalletShouldRefresh,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleActiveAccountChange),
                                               name: .toriiActiveAccountDidChange,
                                               object: nil)
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "paintbrush"),
                                                            style: .plain,
                                                            target: self,
                                                            action: #selector(showThemeSettings))
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "person.crop.circle"),
                                                           style: .plain,
                                                           target: self,
                                                           action: #selector(showAccountSwitcher))
        installOfflineBanner()
        applySoraFonts()
        loadSnapshot()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.tintColor = UIColor.label
        navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.label]
        navigationController?.topViewController?.navigationItem.title = "Wallet"
        tabBarController?.tabBar.tintColor = UIColor.hex(hex: colorHex, alpha: 1)
        tabBarController?.tabBar.isHidden = false
    }

    @objc private func refreshTriggered() {
        loadSnapshot(showLoader: false)
    }

    @objc private func handleWalletRefreshNotification() {
        loadSnapshot(showLoader: false)
    }

    @objc private func handleActiveAccountChange() {
        balanceLabel?.text = formatted(amount: .zero)
        DataManager.instance.balance = .zero
        DataManager.instance.transactions = []
        lastSnapshotFailure = nil
        applySnapshot([])
        tableView.reloadData()
        loadSnapshot(showLoader: true)
    }

    private func loadSnapshot(showLoader: Bool = true) {
        guard let accountId = KeychainManager.instance.accountId else {
            presentRegistrationReset()
            return
        }
        if let lastFailure = lastSnapshotFailure,
           Date().timeIntervalSince(lastFailure) < 20 {
            return
        }
        hideOfflineBanner()

        var alert: PMAlertController?
        if showLoader, isVisibleOnScreen {
            alert = PMAlertController(title: "通信中", description: "ウォレットを更新しています", image: nil, style: .alert)
            if let alert { present(alert, animated: true) }
        }

        Task {
            do {
                let snapshot = try await ToriiService.shared.fetchSnapshot(accountId: accountId)
                lastSnapshotFailure = nil
                let balance = ToriiService.shared.parseBalance(from: snapshot.balances)
                DataManager.instance.balance = balance
                DataManager.instance.transactions = snapshot.transactions
                let formattedBalance = formatted(amount: balance)
                let items = snapshot.transactions.map(TransactionItem.init)
                await MainActor.run {
                    self.balanceLabel?.text = formattedBalance
                    self.applySnapshot(items)
                    alert?.dismiss(animated: true)
                    self.historyRefresh.endRefreshing()
                }
            } catch {
                lastSnapshotFailure = Date()
                await MainActor.run {
                    alert?.dismiss(animated: true)
                    self.historyRefresh.endRefreshing()
                    if self.isNetworkError(error) {
                        self.showOfflineBanner(message: "オフライン: Toriiに接続できません")
                    } else {
                        self.presentError(message: error.localizedDescription)
                    }
                }
            }
        }
    }

    private func formatted(amount: Decimal) -> String {
        "\(amount.plainString) \(config.unit)"
    }

    private func presentError(message: String) {
        guard isVisibleOnScreen else { return }
        let alert = PMAlertController(title: "エラー", description: message, image: nil, style: .alert)
        alert.addAction(PMAlertAction(title: "OK", style: .cancel, action: nil))
        present(alert, animated: true)
    }

    private func presentRegistrationReset() {
        guard isVisibleOnScreen else { return }
        let alert = PMAlertController(title: "アカウントなし", description: "登録画面に戻ります", image: nil, style: .alert)
        alert.addAction(PMAlertAction(title: "OK", style: .default) { [weak self] in
            self?.navigateToRegister()
        })
        present(alert, animated: true)
    }

    @objc private func showThemeSettings() {
        let controller = ThemeSettingsViewController()
        controller.modalPresentationStyle = .pageSheet
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(controller, animated: true)
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

    @objc private func showOfflinePayments() {
        let controller = OfflinePaymentsViewController()
        controller.modalPresentationStyle = .pageSheet
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(controller, animated: true)
    }

    private func navigateToRegister() {
        let onboarding = SoraNexusOnboardingViewController()
        onboarding.onAccountRegistered = { _ in }
        onboarding.modalPresentationStyle = .fullScreen
        present(onboarding, animated: true)
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

    // MARK: - Table view data source

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let container = UIView()
        container.backgroundColor = .clear
        container.applyGlassCardStyle(cornerRadius: 28)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        let headerRow = UIStackView()
        headerRow.axis = .horizontal
        headerRow.alignment = .center
        headerRow.spacing = 10
        stack.addArrangedSubview(headerRow)

        let accent = UIView()
        accent.translatesAutoresizingMaskIntoConstraints = false
        accent.backgroundColor = UIColor.iroha
        accent.layer.cornerRadius = 6
        headerRow.addArrangedSubview(accent)
        accent.enforceHeight(12)
        NSLayoutConstraint.activate([
            accent.widthAnchor.constraint(equalToConstant: 12)
        ])

        let title = UILabel()
        title.text = "残高"
        title.font = UIFont.sora(.semiBold, size: 15)
        title.textColor = UIColor.glassSecondaryText
        title.adjustsFontForContentSizeCategory = true
        headerRow.addArrangedSubview(title)

        let chip = UILabel()
        chip.text = " \(config.assetDisplayName.uppercased()) "
        chip.font = UIFont.sora(.semiBold, size: 12)
        chip.textColor = UIColor.iroha
        chip.backgroundColor = UIColor.iroha.withAlphaComponent(0.12)
        chip.layer.cornerRadius = 12
        chip.layer.masksToBounds = true
        chip.setContentCompressionResistancePriority(.required, for: .horizontal)
        headerRow.addArrangedSubview(chip)
        headerRow.addArrangedSubview(UIView())

        let balanceLabel = UILabel()
        balanceLabel.font = UIFont.sora(.bold, size: 36)
        balanceLabel.adjustsFontForContentSizeCategory = true
        balanceLabel.textColor = UIColor.glassPrimaryText
        balanceLabel.text = formatted(amount: DataManager.instance.balance)
        stack.addArrangedSubview(balanceLabel)
        self.balanceLabel = balanceLabel

        let networkLabel = UILabel()
        networkLabel.font = UIFont.sora(.medium, size: 13)
        networkLabel.textColor = UIColor.glassSecondaryText
        networkLabel.text = "Chain: \(config.chainId)"
        networkLabel.adjustsFontForContentSizeCategory = true
        stack.addArrangedSubview(networkLabel)
        stack.setCustomSpacing(6, after: networkLabel)

        if let account = KeychainManager.instance.activeAccount {
            let accountRow = UIStackView()
            accountRow.axis = .horizontal
            accountRow.alignment = .center
            accountRow.spacing = 10
            accountRow.distribution = .fill
            accountRow.setContentCompressionResistancePriority(.required, for: .horizontal)

            let nameLabel = UILabel()
            nameLabel.font = UIFont.sora(.semiBold, size: 15)
            nameLabel.adjustsFontForContentSizeCategory = true
            nameLabel.textColor = UIColor.glassPrimaryText
            nameLabel.text = account.displayTitle

            let accountLabel = UILabel()
            accountLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
            accountLabel.adjustsFontForContentSizeCategory = true
            accountLabel.textColor = UIColor.glassSecondaryText
            accountLabel.numberOfLines = 0
            accountLabel.text = account.accountId

            let accountStack = UIStackView(arrangedSubviews: [nameLabel, accountLabel])
            accountStack.axis = .vertical
            accountStack.spacing = 2
            accountRow.addArrangedSubview(accountStack)
            accountRow.addArrangedSubview(UIView())

            let copyButton = UIButton(type: .system)
            copyButton.setImage(UIImage(systemName: "doc.on.doc"), for: .normal)
            copyButton.tintColor = UIColor.glassPrimaryText
            copyButton.backgroundColor = UIColor.glassFieldBackground
            copyButton.layer.cornerRadius = 12
            copyButton.setButtonContentInsets(UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10))
            copyButton.setContentHuggingPriority(.required, for: .horizontal)
            let copyAction = UIAction { _ in
                UIPasteboard.general.string = account.receiveAddressLiteral
                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred()
                let announcement = account.accountAlias == nil ? "アカウントIDをコピーしました" : "アカウントエイリアスをコピーしました"
                UIAccessibility.post(notification: .announcement, argument: announcement)
            }
            copyButton.addAction(copyAction, for: .touchUpInside)
            accountRow.addArrangedSubview(copyButton)

            let addButton = UIButton(type: .system)
            addButton.setImage(UIImage(systemName: "person.crop.circle.badge.plus"), for: .normal)
            addButton.tintColor = UIColor.glassPrimaryText
            addButton.backgroundColor = UIColor.glassFieldBackground
            addButton.layer.cornerRadius = 12
            addButton.setButtonContentInsets(UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10))
            addButton.setContentHuggingPriority(.required, for: .horizontal)
            addButton.addAction(UIAction { [weak self] _ in
                self?.presentAdditionalRegistration()
            }, for: .touchUpInside)
            accountRow.addArrangedSubview(addButton)

            let switchButton = UIButton(type: .system)
            switchButton.setImage(UIImage(systemName: "arrow.triangle.2.circlepath"), for: .normal)
            switchButton.tintColor = UIColor.glassPrimaryText
            switchButton.backgroundColor = UIColor.glassFieldBackground
            switchButton.layer.cornerRadius = 12
            switchButton.setButtonContentInsets(UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10))
            switchButton.setContentHuggingPriority(.required, for: .horizontal)
            switchButton.addAction(UIAction { [weak self] _ in
                self?.showAccountSwitcher()
            }, for: .touchUpInside)
            accountRow.addArrangedSubview(switchButton)
            stack.addArrangedSubview(accountRow)
        }

        let actionsRow = UIStackView()
        actionsRow.axis = .horizontal
        actionsRow.spacing = 12
        actionsRow.distribution = .fillEqually
        let sendButton = UIButton(type: .system)
        sendButton.setTitle("Send", for: .normal)
        sendButton.setImage(UIImage(systemName: "arrow.up.right"), for: .normal)
        sendButton.tintColor = .white
        sendButton.applyGlassButtonStyle(accent: UIColor.iroha)
        sendButton.titleLabel?.font = UIFont.sora(.semiBold, size: 16)
        sendButton.contentHorizontalAlignment = .center
        sendButton.setButtonContentInsets(UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16))
        sendButton.enforceHeight(52)
        sendButton.setButtonImagePadding(6)
        let sendAction = UIAction { [weak self] _ in
            let feedback = UIImpactFeedbackGenerator(style: .medium)
            feedback.impactOccurred()
            guard let tabBar = self?.tabBarController else { return }
            if let index = tabBar.viewControllers?.firstIndex(where: { viewController in
                if let navigation = viewController as? UINavigationController {
                    return navigation.viewControllers.contains(where: { $0 is SendViewController })
                }
                return viewController is SendViewController
            }) {
                tabBar.selectedIndex = index
            }
        }
        sendButton.addAction(sendAction, for: .touchUpInside)

        let receiveButton = UIButton(type: .system)
        receiveButton.setTitle("Receive", for: .normal)
        receiveButton.setImage(UIImage(systemName: "arrow.down.left"), for: .normal)
        receiveButton.tintColor = .white
        receiveButton.applyGlassButtonStyle(accent: UIColor.irohaGreen)
        receiveButton.titleLabel?.font = UIFont.sora(.semiBold, size: 16)
        receiveButton.contentHorizontalAlignment = .center
        receiveButton.setButtonContentInsets(UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16))
        receiveButton.enforceHeight(52)
        receiveButton.setButtonImagePadding(6)
        let receiveAction = UIAction { [weak self] _ in
            let feedback = UIImpactFeedbackGenerator(style: .medium)
            feedback.impactOccurred()
            guard let tabBar = self?.tabBarController else { return }
            if let index = tabBar.viewControllers?.firstIndex(where: { viewController in
                if let navigation = viewController as? UINavigationController {
                    return navigation.viewControllers.contains(where: { $0 is ReceiveViewController })
                }
                return viewController is ReceiveViewController
            }) {
                tabBar.selectedIndex = index
            }
        }
        receiveButton.addAction(receiveAction, for: .touchUpInside)
        let offlineButton = UIButton(type: .system)
        offlineButton.setTitle("Offline", for: .normal)
        offlineButton.setImage(UIImage(systemName: "bolt.horizontal.circle"), for: .normal)
        offlineButton.tintColor = .white
        offlineButton.applyGlassButtonStyle(accent: UIColor.systemIndigo)
        offlineButton.titleLabel?.font = UIFont.sora(.semiBold, size: 16)
        offlineButton.contentHorizontalAlignment = .center
        offlineButton.setButtonContentInsets(UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16))
        offlineButton.enforceHeight(52)
        offlineButton.setButtonImagePadding(6)
        offlineButton.addAction(UIAction { [weak self] _ in
            let feedback = UIImpactFeedbackGenerator(style: .medium)
            feedback.impactOccurred()
            self?.showOfflinePayments()
        }, for: .touchUpInside)
        actionsRow.addArrangedSubview(sendButton)
        actionsRow.addArrangedSubview(receiveButton)
        actionsRow.addArrangedSubview(offlineButton)
        stack.setCustomSpacing(18, after: balanceLabel)
        stack.addArrangedSubview(actionsRow)

        container.layoutIfNeeded()
        sendButton.refreshGlassButtonStyleLayout()
        receiveButton.refreshGlassButtonStyleLayout()
        offlineButton.refreshGlassButtonStyleLayout()

        container.applySoraFontsRecursively()
        return container
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        UITableView.automaticDimension
    }

    override func tableView(_ tableView: UITableView, estimatedHeightForHeaderInSection section: Int) -> CGFloat {
        160
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Diffable data source

    private func configureDataSource() {
        dataSource = UITableViewDiffableDataSource<Section, TransactionItem>(tableView: tableView) { [weak self] tableView, indexPath, item in
            guard let cell = tableView.dequeueReusableCell(withIdentifier: "TransactionCell", for: indexPath) as? TransactionCell else {
                return UITableViewCell()
            }
            let accountId = KeychainManager.instance.accountId
            cell.configure(with: item.transaction, currentAccountId: accountId, unit: self?.config.unit ?? "")
            return cell
        }
        tableView.dataSource = dataSource
        applySnapshot([])
    }

    private func applySnapshot(_ items: [TransactionItem]) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, TransactionItem>()
        snapshot.appendSections([.main])
        snapshot.appendItems(items, toSection: .main)
        dataSource.apply(snapshot, animatingDifferences: true)
    }
}

// MARK: - Account switcher

final class AccountSwitcherViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    var onAddAccount: (() -> Void)?

    private var accounts: [StoredAccount] = []
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyLabel = UILabel()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let addButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        configureLayout()
        reloadAccounts()
        applySoraFonts()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadAccounts()
    }

    private func configureLayout() {
        installGlassBackground()
        view.backgroundColor = .clear

        titleLabel.text = "アカウントを切り替え"
        titleLabel.font = UIFont.sora(.bold, size: 24)
        titleLabel.textColor = UIColor.glassPrimaryText
        titleLabel.numberOfLines = 0

        subtitleLabel.text = "複数のSORA Nexusアカウントを登録して、ここから素早く切り替えられます。"
        subtitleLabel.font = UIFont.sora(.regular, size: 14)
        subtitleLabel.textColor = UIColor.glassSecondaryText
        subtitleLabel.numberOfLines = 0

        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = UIColor.glassPrimaryText
        closeButton.backgroundColor = UIColor.glassFieldBackground
        closeButton.layer.cornerRadius = 16
        closeButton.setButtonContentInsets(UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8))
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)

        let headerStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        headerStack.axis = .vertical
        headerStack.spacing = 6
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerStack)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(AccountCell.self, forCellReuseIdentifier: "AccountCell")
        tableView.estimatedRowHeight = 88
        tableView.rowHeight = UITableView.automaticDimension
        view.addSubview(tableView)

        emptyLabel.text = "まだアカウントがありません。新規登録してください。"
        emptyLabel.textAlignment = .center
        emptyLabel.textColor = UIColor.glassSecondaryText
        emptyLabel.font = UIFont.sora(.medium, size: 14)
        emptyLabel.numberOfLines = 0
        tableView.backgroundView = emptyLabel

        addButton.applyGlassButtonStyle()
        addButton.setTitle("新しいアカウントを登録", for: .normal)
        addButton.setImage(UIImage(systemName: "person.crop.circle.badge.plus"), for: .normal)
        addButton.tintColor = .white
        addButton.enforceHeight(52)
        addButton.semanticContentAttribute = .forceLeftToRight
        addButton.setButtonImagePadding(8)
        addButton.addTarget(self, action: #selector(addAccountTapped), for: .touchUpInside)
        addButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(addButton)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            headerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            headerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            headerStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),

            addButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            addButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            addButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),

            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 16),
            tableView.bottomAnchor.constraint(equalTo: addButton.topAnchor, constant: -16)
        ])
    }

    private func reloadAccounts() {
        accounts = KeychainManager.instance.storedAccounts
        tableView.reloadData()
        emptyLabel.isHidden = !accounts.isEmpty
    }

    @objc private func addAccountTapped() {
        dismiss(animated: true) { [weak self] in
            self?.onAddAccount?()
        }
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        accounts.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "AccountCell", for: indexPath) as? AccountCell else {
            return UITableViewCell()
        }
        let account = accounts[indexPath.row]
        let isActive = account.accountId == KeychainManager.instance.accountId
        cell.configure(with: account, isActive: isActive)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let account = accounts[indexPath.row]
        guard account.accountId != KeychainManager.instance.accountId else {
            dismiss(animated: true)
            return
        }
        _ = KeychainManager.instance.switchActiveAccount(to: account.accountId)
        DataManager.instance.balance = .zero
        DataManager.instance.transactions = []
        dismiss(animated: true)
    }
}

private final class AccountCell: UITableViewCell {
    private let card = UIView()
    private let nameLabel = UILabel()
    private let accountLabel = UILabel()
    private let statusChip = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure() {
        card.translatesAutoresizingMaskIntoConstraints = false
        card.applyGlassCardStyle(cornerRadius: 18)
        contentView.addSubview(card)

        nameLabel.font = UIFont.sora(.semiBold, size: 16)
        nameLabel.textColor = UIColor.glassPrimaryText
        nameLabel.numberOfLines = 1

        accountLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        accountLabel.textColor = UIColor.glassSecondaryText
        accountLabel.numberOfLines = 1

        statusChip.font = UIFont.sora(.semiBold, size: 12)
        statusChip.textColor = UIColor.iroha
        statusChip.backgroundColor = UIColor.iroha.withAlphaComponent(0.14)
        statusChip.layer.cornerRadius = 10
        statusChip.layer.masksToBounds = true
        statusChip.text = "使用中"
        statusChip.textAlignment = .center
        statusChip.isHidden = true
        statusChip.translatesAutoresizingMaskIntoConstraints = false
        statusChip.setContentHuggingPriority(.required, for: .horizontal)

        let textStack = UIStackView(arrangedSubviews: [nameLabel, accountLabel])
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let row = UIStackView(arrangedSubviews: [textStack, statusChip])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(row)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),

            row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            row.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),

            statusChip.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    func configure(with account: StoredAccount, isActive: Bool) {
        nameLabel.text = account.displayTitle
        accountLabel.text = account.shortAccountId
        statusChip.isHidden = !isActive
    }
}

// MARK: - Offline payments

@MainActor
protocol OfflineAllowanceProviding {
    var config: ToriiConfiguration { get }
    func fetchOfflineAllowances(limit: UInt64,
                                includeExpired: Bool) async throws -> ToriiOfflineAllowanceList
}

extension ToriiService: OfflineAllowanceProviding {}

@MainActor
protocol OfflineTransferListing {
    func fetchOfflineTransfers(limit: UInt64,
                               filter: String?,
                               controllerAccountId: String?,
                               receiverAccountId: String?,
                               depositAccountId: String?) async throws -> ToriiOfflineTransferList
}

@MainActor
protocol OfflineRedemptionSubmitting {
    var isMockSubmission: Bool { get }
    func submitRedeemedVouchers(_ vouchers: [OfflinePaymentVoucher]) async throws -> OfflinePaymentManager.OfflineTransferReceipt
}

enum OfflinePaymentError: LocalizedError {
    case noAllowances
    case invalidAmount
    case insufficientAllowance
    case missingAccount
    case invalidPayload
    case alreadyRedeemed
    case nothingToTransfer
    case apiUnavailable

    var errorDescription: String? {
        switch self {
        case .noAllowances:
            return "オフライン残高がありません。トップアップを取得してください。"
        case .invalidAmount:
            return "金額が無効です。"
        case .insufficientAllowance:
            return "指定した金額は単発送金上限を超えています。1件ごとの上限以内に分割してください。"
        case .missingAccount:
            return "アカウント情報がありません。"
        case .invalidPayload:
            return "共有ペイロードを作成できませんでした。"
        case .alreadyRedeemed:
            return "このバウチャーはすでに取り込み済みです。"
        case .nothingToTransfer:
            return "オンラインへ戻すバウチャーがありません。"
        case .apiUnavailable:
            return "ToriiのオフラインAPIにアクセスできません。"
        }
    }
}

struct OfflinePaymentVoucher: Codable, Equatable {
    let id: String
    let senderId: String
    let receiverId: String
    let assetId: String
    let amount: String
    let certificateIdHex: String
    let issuedAtMs: UInt64
    let note: String?
    let mode: OfflineWalletCirculationMode

    var payloadData: Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(self)
    }

    var qrPayloadString: String? {
        guard let data = payloadData else { return nil }
        return String(data: data, encoding: .utf8)
    }

    var txId: Data? {
        guard let data = payloadData else { return nil }
        let digest = SHA256.hash(data: data)
        return Data(digest)
    }
}

@MainActor
final class OfflinePaymentManager {
    static let shared = OfflinePaymentManager(submitter: ToriiService.shared)

    private let service: OfflineAllowanceProviding
    private let submitter: OfflineRedemptionSubmitting?
    private let transferProvider: OfflineTransferListing?
    private var allowances: [ToriiOfflineAllowanceItem] = []
    private var allowanceBalances: [String: Decimal] = [:]
    private var lastRefreshed: Date?
    private let journal: OfflineJournal?
    private let unit: String
    private let accountResolver: () -> String?
    private let redeemedStore: UserDefaults

    init(service: OfflineAllowanceProviding = ToriiService.shared,
         journalURL: URL? = nil,
         journalKeySeed: Data? = nil,
         accountResolver: @escaping () -> String? = { KeychainManager.instance.accountId },
         redeemedStore: UserDefaults = .standard,
         submitter: OfflineRedemptionSubmitting? = nil,
         transferProvider: OfflineTransferListing? = nil) {
        self.service = service
        self.unit = service.config.unit
        self.accountResolver = accountResolver
        self.redeemedStore = redeemedStore
        self.submitter = submitter
        self.transferProvider = transferProvider ?? (service as? OfflineTransferListing)
        let storageURL = journalURL ?? OfflinePaymentManager.defaultJournalURL()
        let keySeed = journalKeySeed ?? OfflinePaymentManager.defaultKeySeed()
        self.journal = OfflinePaymentManager.makeJournal(url: storageURL, seed: keySeed)
    }

    func refreshAllowances(limit: UInt64 = 50) async throws -> [ToriiOfflineAllowanceItem] {
        let list = try await service.fetchOfflineAllowances(limit: limit, includeExpired: false)
        allowances = list.items
        allowanceBalances = Dictionary(
            uniqueKeysWithValues: allowances.map { item in
                let remaining = item.remainingAmountDecimal ?? .zero
                return (item.certificateIdHex.lowercased(), remaining)
            }
        )
        lastRefreshed = Date()
        return allowances
    }

    var totalRemaining: Decimal {
        allowanceBalances.values.reduce(Decimal.zero, +)
    }

    var maxSingleRemaining: Decimal {
        allowanceBalances.values.max() ?? .zero
    }

    var lastUpdatedText: String {
        guard let refreshed = lastRefreshed else {
            return "未取得"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: refreshed)
    }

    var hasOnlineSubmitter: Bool {
        submitter != nil
    }

    var isMockSubmission: Bool {
        submitter?.isMockSubmission ?? true
    }

    func fetchRemoteTransfers(limit: UInt64 = 5,
                              depositAccountId: String? = nil,
                              filter: String? = nil) async throws -> ToriiOfflineTransferList {
        guard let transferProvider else { throw OfflinePaymentError.apiUnavailable }
        guard let account = accountResolver() else { throw OfflinePaymentError.missingAccount }
        let deposit = depositAccountId ?? account
        return try await transferProvider.fetchOfflineTransfers(limit: limit,
                                                                filter: filter,
                                                                controllerAccountId: account,
                                                                receiverAccountId: account,
                                                                depositAccountId: deposit)
    }

    func createVoucher(receiverId: String,
                       amount: Decimal,
                       note: String?,
                       mode: OfflineWalletCirculationMode) throws -> OfflinePaymentVoucher {
        guard let sender = accountResolver(),
              let canonicalSender = AccountIdentity.normalizedAccountId(sender) else {
            throw OfflinePaymentError.missingAccount
        }
        guard let normalizedReceiver = AccountIdentity.normalizedReference(receiverId) else {
            throw OfflinePaymentError.invalidPayload
        }
        guard !allowances.isEmpty else {
            throw OfflinePaymentError.noAllowances
        }
        guard amount > 0 else {
            throw OfflinePaymentError.invalidAmount
        }
        guard maxSingleRemaining >= amount else {
            throw OfflinePaymentError.insufficientAllowance
        }
        guard let chosen = pickAllowance(for: amount) else {
            throw OfflinePaymentError.insufficientAllowance
        }
        let issuedAt = UInt64(Date().timeIntervalSince1970 * 1_000)
        let voucher = OfflinePaymentVoucher(id: UUID().uuidString,
                                            senderId: canonicalSender,
                                            receiverId: normalizedReceiver,
                                            assetId: chosen.assetId,
                                            amount: amount.plainString,
                                            certificateIdHex: chosen.certificateIdHex,
                                            issuedAtMs: issuedAt,
                                            note: note,
                                            mode: mode)
        guard let payload = voucher.payloadData,
              let txId = voucher.txId else {
            throw OfflinePaymentError.invalidPayload
        }
        _ = try journal?.appendPending(txId: txId, payload: payload, timestampMs: issuedAt)
        return voucher
    }

    func validateVoucherPayload(_ payload: String) throws -> OfflinePaymentVoucher {
        guard let data = payload.data(using: .utf8) else {
            throw OfflinePaymentError.invalidPayload
        }
        let voucher = try JSONDecoder().decode(OfflinePaymentVoucher.self, from: data)
        guard let txIdHex = voucher.txId?.hexEncodedString() else {
            throw OfflinePaymentError.invalidPayload
        }
        if redeemedTxIds.contains(txIdHex) {
            throw OfflinePaymentError.alreadyRedeemed
        }
        return voucher
    }

    func markVoucherRedeemed(_ voucher: OfflinePaymentVoucher) {
        guard let txHex = voucher.txId?.hexEncodedString() else { return }
        var set = redeemedTxIds
        set.insert(txHex)
        redeemedStore.set(Array(set), forKey: Self.redeemedKey)
        if let payload = voucher.qrPayloadString {
            storeRedeemedPayload(payload, for: txHex)
        }
    }

    func isVoucherRedeemed(_ voucher: OfflinePaymentVoucher) -> Bool {
        guard let txHex = voucher.txId?.hexEncodedString() else { return false }
        return redeemedTxIds.contains(txHex)
    }

    func redeemedVouchers() -> [OfflinePaymentVoucher] {
        redeemedPayloads.values.compactMap { payload in
            guard let data = payload.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(OfflinePaymentVoucher.self, from: data)
        }
    }

    var redeemedTotal: Decimal {
        redeemedVouchers().reduce(.zero) { partial, voucher in
            let amount = Decimal(string: voucher.amount) ?? .zero
            return partial + amount
        }
    }

    func exportRedeemedJSON(pretty: Bool = true) -> String? {
        let vouchers = redeemedVouchers()
        guard !vouchers.isEmpty else { return nil }
        let encoder = JSONEncoder()
        if pretty { encoder.outputFormatting = [.prettyPrinted, .sortedKeys] }
        guard let data = try? encoder.encode(vouchers) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    struct OfflineTransferReceipt: Codable, Equatable {
        let movedAmount: Decimal
        let voucherCount: Int
        let completedAt: Date
    }

    func transferRedeemedToOnline() async throws -> OfflineTransferReceipt {
        let vouchers = redeemedVouchers()
        guard !vouchers.isEmpty else { throw OfflinePaymentError.nothingToTransfer }
        if let submitter {
            let receipt = try await submitter.submitRedeemedVouchers(vouchers)
            clearRedeemed()
            return receipt
        }
        return try simulateOnlineTransfer()
    }

    /// Simulates moving redeemed vouchers back to the online balance.
    func simulateOnlineTransfer() throws -> OfflineTransferReceipt {
        let vouchers = redeemedVouchers()
        guard !vouchers.isEmpty else { throw OfflinePaymentError.nothingToTransfer }
        let receipt = OfflineTransferReceipt(movedAmount: redeemedTotal,
                                             voucherCount: vouchers.count,
                                             completedAt: Date())
        clearRedeemed()
        return receipt
    }

    func clearRedeemed() {
        redeemedStore.removeObject(forKey: Self.redeemedKey)
        redeemedStore.removeObject(forKey: Self.redeemedPayloadsKey)
    }

    func allowanceList() -> [ToriiOfflineAllowanceItem] {
        allowances
    }

    func formattedAmount(_ amount: Decimal) -> String {
        "\(amount.plainString) \(unit)"
    }

    // MARK: - Redemption persistence

    private static let redeemedKey = "offline.redeemed.txids"
    private static let redeemedPayloadsKey = "offline.redeemed.payloads"

    private var redeemedTxIds: Set<String> {
        let array = redeemedStore.stringArray(forKey: Self.redeemedKey) ?? []
        return Set(array)
    }

    private var redeemedPayloads: [String: String] {
        redeemedStore.dictionary(forKey: Self.redeemedPayloadsKey) as? [String: String] ?? [:]
    }

    private func storeRedeemedPayload(_ payload: String, for txHex: String) {
        var dict = redeemedPayloads
        dict[txHex] = payload
        redeemedStore.set(Array(redeemedTxIds.union([txHex])), forKey: Self.redeemedKey)
        redeemedStore.set(dict, forKey: Self.redeemedPayloadsKey)
    }

    // MARK: - Private helpers

    private func pickAllowance(for amount: Decimal) -> ToriiOfflineAllowanceItem? {
        guard let match = allowances.first(where: { item in
            let balance = allowanceBalances[item.certificateIdHex.lowercased()] ?? .zero
            return balance >= amount
        }) else {
            return nil
        }
        let key = match.certificateIdHex.lowercased()
        let current = allowanceBalances[key] ?? .zero
        allowanceBalances[key] = max(.zero, current - amount)
        return match
    }

    private static func defaultJournalURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return (base ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("offline")
            .appendingPathComponent("journal.bin")
    }

    private static func defaultKeySeed() -> Data {
        if let hex = KeychainManager.instance.privateKeyHex,
           let data = Data(hexString: hex) {
            return data
        }
        return Data("offline-journal".utf8)
    }

    private static func makeJournal(url: URL, seed: Data) -> OfflineJournal? {
        do {
            let key = OfflineJournalKey.derive(from: seed)
            return try OfflineJournal(url: url, key: key)
        } catch {
            return nil
        }
    }
}

@MainActor
final class OfflinePaymentsViewController: UIViewController {
    private let manager = OfflinePaymentManager.shared
    private var allowances: [ToriiOfflineAllowanceItem] = []
    private var currentVoucher: OfflinePaymentVoucher?
#if canImport(CoreNFC) && !targetEnvironment(simulator)
    private var nfcSession: NFCNDEFReaderSession?
#endif
    private var pendingNdefPayload: String?
    private var importedVoucher: OfflinePaymentVoucher?

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let balanceLabel = UILabel()
    private let lastUpdatedLabel = UILabel()
    private let allowanceListStack = UIStackView()
    private let receiverField = UITextField()
    private let amountField = UITextField()
    private let noteField = UITextField()
    private let modeControl = UISegmentedControl(items: ["Ledger", "Offline"])
    private let modeNoticeLabel = UILabel()
    private let qrImageView = UIImageView()
    private let voucherInfoLabel = UILabel()
    private let shareButton = UIButton(type: .system)
    private let nfcButton = UIButton(type: .system)
    private let voucherPayloadView = UITextView()
    private let receiveInfoLabel = UILabel()
    private let redeemButton = UIButton(type: .system)
    private let reconciliationInfoLabel = UILabel()
    private let reconcileButton = UIButton(type: .system)
    private let redeemedListStack = UIStackView()
    private let serverTransfersLabel = UILabel()
    private let serverTransfersButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        configureLayout()
        installGlassBackground()
        applySoraFonts()
        updateReconciliationInfo()
        renderRedeemedList()
        Task { await refreshAllowances() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        shareButton.refreshGlassButtonStyleLayout()
        nfcButton.refreshGlassButtonStyleLayout()
        reconcileButton.refreshGlassButtonStyleLayout()
        serverTransfersButton.refreshGlassButtonStyleLayout()
    }

    private func configureLayout() {
        view.backgroundColor = .clear
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 32, right: 0)
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        contentStack.axis = .vertical
        contentStack.spacing = 16
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 12),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40)
        ])

        contentStack.addArrangedSubview(makeHeader())
        contentStack.addArrangedSubview(makeAllowanceCard())
        contentStack.addArrangedSubview(makeComposerCard())
        contentStack.addArrangedSubview(makeReceiveCard())
        contentStack.addArrangedSubview(makeVoucherCard())
    }

    private func makeHeader() -> UIView {
        let title = UILabel()
        title.text = "オフライン決済"
        title.font = UIFont.sora(.bold, size: 26)
        title.textColor = UIColor.glassPrimaryText
        title.numberOfLines = 0

        let subtitle = UILabel()
        subtitle.text = "トップアップを取得し、QR / Bluetooth / NFCで支払います。"
        subtitle.font = UIFont.sora(.regular, size: 14)
        subtitle.textColor = UIColor.glassSecondaryText
        subtitle.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [title, subtitle])
        stack.axis = .vertical
        stack.spacing = 6
        return stack
    }

    private func makeAllowanceCard() -> UIView {
        let container = UIView()
        container.applyGlassCardStyle(cornerRadius: 20)

        let title = UILabel()
        title.text = "オフライントップアップ"
        title.font = UIFont.sora(.semiBold, size: 16)
        title.textColor = UIColor.glassPrimaryText

        balanceLabel.font = UIFont.sora(.bold, size: 32)
        balanceLabel.textColor = UIColor.glassPrimaryText
        balanceLabel.numberOfLines = 1
        balanceLabel.text = "単発送金上限 \(manager.formattedAmount(.zero))"

        lastUpdatedLabel.font = UIFont.sora(.medium, size: 12)
        lastUpdatedLabel.textColor = UIColor.glassSecondaryText
        lastUpdatedLabel.text = "最終更新: \(manager.lastUpdatedText)"

        let refreshButton = UIButton(type: .system)
        refreshButton.setTitle("トップアップを取得", for: .normal)
        refreshButton.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
        refreshButton.tintColor = .white
        refreshButton.applyGlassButtonStyle(accent: UIColor.irohaGreen)
        refreshButton.enforceHeight(44)
        refreshButton.setButtonImagePadding(6)
        refreshButton.addAction(UIAction { [weak self] _ in
            Task { await self?.refreshAllowances() }
        }, for: .touchUpInside)

        let helpButton = UIButton(type: .system)
        helpButton.setTitle("トップアップの流れを確認", for: .normal)
        helpButton.setImage(UIImage(systemName: "questionmark.circle"), for: .normal)
        helpButton.tintColor = UIColor.glassPrimaryText
        helpButton.applyGlassButtonStyle(accent: UIColor.glassFieldBackground)
        helpButton.setTitleColor(UIColor.glassPrimaryText, for: .normal)
        helpButton.enforceHeight(38)
        helpButton.setButtonImagePadding(6)
        helpButton.addAction(UIAction { [weak self] _ in
            self?.presentTopUpInfo()
        }, for: .touchUpInside)

        allowanceListStack.axis = .vertical
        allowanceListStack.spacing = 8

        let stack = UIStackView(arrangedSubviews: [title, balanceLabel, lastUpdatedLabel, allowanceListStack, refreshButton, helpButton])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16)
        ])
        return container
    }

    private func makeComposerCard() -> UIView {
        let container = UIView()
        container.applyGlassCardStyle(cornerRadius: 20)

        let title = UILabel()
        title.text = "オフラインバウチャーを作成"
        title.font = UIFont.sora(.semiBold, size: 16)
        title.textColor = UIColor.glassPrimaryText

        [receiverField, amountField, noteField].forEach { field in
            field.borderStyle = .roundedRect
            field.applyGlassInputStyle()
            field.enforceHeight(50)
            field.font = UIFont.sora(.medium, size: 15)
            field.autocorrectionType = .no
            field.autocapitalizationType = .none
        }
        receiverField.placeholder = "受取アカウントID / エイリアス"
        amountField.placeholder = "金額 (\(ToriiService.shared.config.unit))"
        amountField.keyboardType = .decimalPad
        noteField.placeholder = "メモ (任意)"

        modeControl.selectedSegmentIndex = 0
        modeControl.selectedSegmentTintColor = UIColor.iroha
        modeControl.backgroundColor = UIColor.glassFieldBackground
        modeControl.addAction(UIAction { [weak self] _ in
            self?.updateModeNotice()
        }, for: .valueChanged)

        modeNoticeLabel.font = UIFont.sora(.regular, size: 12)
        modeNoticeLabel.textColor = UIColor.glassSecondaryText
        modeNoticeLabel.numberOfLines = 0
        updateModeNotice()

        let createButton = UIButton(type: .system)
        createButton.setTitle("バウチャーを生成", for: .normal)
        createButton.setImage(UIImage(systemName: "qrcode"), for: .normal)
        createButton.tintColor = .white
        createButton.applyGlassButtonStyle(accent: UIColor.iroha)
        createButton.enforceHeight(48)
        createButton.setButtonImagePadding(6)
        createButton.addAction(UIAction { [weak self] _ in
            self?.createVoucher()
        }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [
            title,
            receiverField,
            amountField,
            noteField,
            modeControl,
            modeNoticeLabel,
            createButton
        ])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16)
        ])
        return container
    }

    private func makeVoucherCard() -> UIView {
        let container = UIView()
        container.applyGlassCardStyle(cornerRadius: 20)

        let title = UILabel()
        title.text = "共有とバックアップ"
        title.font = UIFont.sora(.semiBold, size: 16)
        title.textColor = UIColor.glassPrimaryText

        qrImageView.contentMode = .scaleAspectFit
        qrImageView.layer.cornerRadius = 16
        qrImageView.layer.masksToBounds = true
        qrImageView.backgroundColor = UIColor.glassFieldBackground
        qrImageView.enforceHeight(220)

        voucherInfoLabel.font = UIFont.sora(.regular, size: 13)
        voucherInfoLabel.textColor = UIColor.glassSecondaryText
        voucherInfoLabel.numberOfLines = 0
        voucherInfoLabel.text = "バウチャーを生成するとここに表示されます。"

        shareButton.setTitle("AirDrop / Bluetooth", for: .normal)
        shareButton.setImage(UIImage(systemName: "square.and.arrow.up"), for: .normal)
        shareButton.tintColor = .white
        shareButton.applyGlassButtonStyle(accent: UIColor.irohaGreen)
        shareButton.enforceHeight(44)
        shareButton.setButtonImagePadding(6)
        shareButton.addAction(UIAction { [weak self] _ in
            self?.presentShareSheet()
        }, for: .touchUpInside)

        nfcButton.setTitle("NFCで送信", for: .normal)
        nfcButton.setImage(UIImage(systemName: "radiowaves.left"), for: .normal)
        nfcButton.tintColor = .white
        nfcButton.applyGlassButtonStyle(accent: UIColor.systemIndigo)
        nfcButton.enforceHeight(44)
        nfcButton.setButtonImagePadding(6)
        nfcButton.addAction(UIAction { [weak self] _ in
            self?.writeNFC()
        }, for: .touchUpInside)

        let buttonRow = UIStackView(arrangedSubviews: [shareButton, nfcButton])
        buttonRow.axis = .horizontal
        buttonRow.spacing = 12
        buttonRow.distribution = .fillEqually

        let stack = UIStackView(arrangedSubviews: [title, qrImageView, voucherInfoLabel, buttonRow])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16)
        ])
        return container
    }

    private func makeReceiveCard() -> UIView {
        let container = UIView()
        container.applyGlassCardStyle(cornerRadius: 20)

        let title = UILabel()
        title.text = "バウチャーを取り込む"
        title.font = UIFont.sora(.semiBold, size: 16)
        title.textColor = UIColor.glassPrimaryText

        voucherPayloadView.backgroundColor = UIColor.glassFieldBackground
        voucherPayloadView.textColor = UIColor.glassPrimaryText
        voucherPayloadView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        voucherPayloadView.layer.cornerRadius = 14
        voucherPayloadView.layer.masksToBounds = true
        voucherPayloadView.enforceHeight(110)

        receiveInfoLabel.font = UIFont.sora(.regular, size: 13)
        receiveInfoLabel.textColor = UIColor.glassSecondaryText
        receiveInfoLabel.numberOfLines = 0
        receiveInfoLabel.text = "QR / NFC / ペイロードを読み取るとここに詳細が表示されます。"

        let pasteButton = UIButton(type: .system)
        pasteButton.setTitle("クリップボードから貼り付け", for: .normal)
        pasteButton.setImage(UIImage(systemName: "doc.on.clipboard"), for: .normal)
        pasteButton.tintColor = .white
        pasteButton.applyGlassButtonStyle(accent: UIColor.systemTeal)
        pasteButton.enforceHeight(44)
        pasteButton.setButtonImagePadding(6)
        pasteButton.addAction(UIAction { [weak self] _ in
            self?.handleClipboardImport()
        }, for: .touchUpInside)

        let scanButton = UIButton(type: .system)
        scanButton.setTitle("QRをスキャン", for: .normal)
        scanButton.setImage(UIImage(systemName: "camera.viewfinder"), for: .normal)
        scanButton.tintColor = .white
        scanButton.applyGlassButtonStyle(accent: UIColor.systemOrange)
        scanButton.enforceHeight(44)
        scanButton.setButtonImagePadding(6)
        scanButton.addAction(UIAction { [weak self] _ in
            self?.presentScanner()
        }, for: .touchUpInside)

        redeemButton.setTitle("取り込み済みにする", for: .normal)
        redeemButton.setImage(UIImage(systemName: "checkmark.seal"), for: .normal)
        redeemButton.tintColor = .white
        redeemButton.applyGlassButtonStyle(accent: UIColor.systemPurple)
        redeemButton.enforceHeight(44)
        redeemButton.setButtonImagePadding(6)
        redeemButton.isEnabled = false
        redeemButton.alpha = 0.6
        redeemButton.addAction(UIAction { [weak self] _ in
            self?.redeemImportedVoucher()
        }, for: .touchUpInside)

        reconciliationInfoLabel.font = UIFont.sora(.regular, size: 13)
        reconciliationInfoLabel.textColor = UIColor.glassSecondaryText
        reconciliationInfoLabel.numberOfLines = 0
        reconciliationInfoLabel.text = "オンライン残高へ戻すバウチャーはありません。"

        reconcileButton.setTitle("オンライン残高に戻す", for: .normal)
        reconcileButton.setImage(UIImage(systemName: "arrow.triangle.2.circlepath"), for: .normal)
        reconcileButton.tintColor = .white
        reconcileButton.applyGlassButtonStyle(accent: UIColor.irohaGreen)
        reconcileButton.enforceHeight(44)
        reconcileButton.setButtonImagePadding(6)
        reconcileButton.addAction(UIAction { [weak self] _ in
            self?.presentReconcileOptions()
        }, for: .touchUpInside)

        serverTransfersLabel.font = UIFont.sora(.regular, size: 12)
        serverTransfersLabel.textColor = UIColor.glassSecondaryText
        serverTransfersLabel.numberOfLines = 0
        serverTransfersLabel.text = "Toriiキュー: 未取得"

        serverTransfersButton.setTitle("Toriiのキューを確認", for: .normal)
        serverTransfersButton.setImage(UIImage(systemName: "arrow.clockwise.circle"), for: .normal)
        serverTransfersButton.tintColor = .white
        serverTransfersButton.applyGlassButtonStyle(accent: UIColor.systemBlue.withAlphaComponent(0.85))
        serverTransfersButton.enforceHeight(38)
        serverTransfersButton.setButtonImagePadding(6)
        serverTransfersButton.addAction(UIAction { [weak self] _ in
            Task { await self?.refreshServerTransfers() }
        }, for: .touchUpInside)

        let redeemedTitle = UILabel()
        redeemedTitle.text = "取り込み済み"
        redeemedTitle.font = UIFont.sora(.semiBold, size: 14)
        redeemedTitle.textColor = UIColor.glassPrimaryText

        redeemedListStack.axis = .vertical
        redeemedListStack.spacing = 6

        let clearButton = UIButton(type: .system)
        clearButton.setTitle("取り込み履歴をクリア", for: .normal)
        clearButton.setImage(UIImage(systemName: "trash"), for: .normal)
        clearButton.tintColor = .white
        clearButton.applyGlassButtonStyle(accent: UIColor.systemRed.withAlphaComponent(0.7))
        clearButton.enforceHeight(38)
        clearButton.setButtonImagePadding(6)
        clearButton.addAction(UIAction { [weak self] _ in
            self?.clearRedeemedHistory()
        }, for: .touchUpInside)

        let buttons = UIStackView(arrangedSubviews: [
            pasteButton,
            scanButton,
            redeemButton,
            reconciliationInfoLabel,
            reconcileButton,
            serverTransfersLabel,
            serverTransfersButton,
            redeemedTitle,
            redeemedListStack,
            clearButton
        ])
        buttons.axis = .vertical
        buttons.spacing = 10

        let stack = UIStackView(arrangedSubviews: [title, receiveInfoLabel, voucherPayloadView, buttons])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16)
        ])
        return container
    }

    // MARK: - Actions

    private func updateModeNotice() {
        let mode: OfflineWalletCirculationMode = modeControl.selectedSegmentIndex == 0 ? .ledgerReconcilable : .offlineOnly
        modeNoticeLabel.text = mode.notice.details
    }

    @MainActor
    private func refreshAllowances() async {
        do {
            allowances = try await manager.refreshAllowances(limit: 100)
            balanceLabel.text = "単発送金上限 \(manager.formattedAmount(manager.maxSingleRemaining))"
            lastUpdatedLabel.text = "最終更新: \(manager.lastUpdatedText) / 合計 \(manager.formattedAmount(manager.totalRemaining))"
            renderAllowanceList()
        } catch {
            presentError(message: error.localizedDescription)
        }
    }

    private func renderAllowanceList() {
        allowanceListStack.arrangedSubviews.forEach { view in
            allowanceListStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        if allowances.isEmpty {
            let label = UILabel()
            label.text = "まだオフライン残高がありません。オンラインでトップアップを取得してください。"
            label.font = UIFont.sora(.regular, size: 13)
            label.textColor = UIColor.glassSecondaryText
            label.numberOfLines = 0
            allowanceListStack.addArrangedSubview(label)
            return
        }
        allowances.forEach { allowance in
            let badge = makeAllowanceRow(allowance)
            allowanceListStack.addArrangedSubview(badge)
        }
    }

    private func makeAllowanceRow(_ allowance: ToriiOfflineAllowanceItem) -> UIView {
        let chip = UIView()
        chip.backgroundColor = UIColor.glassFieldBackground
        chip.layer.cornerRadius = 12

        let title = UILabel()
        title.font = UIFont.sora(.semiBold, size: 14)
        title.textColor = UIColor.glassPrimaryText
        title.text = allowance.assetId

        let remaining = UILabel()
        remaining.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .medium)
        remaining.textColor = UIColor.glassSecondaryText
        remaining.text = "残高 \(allowance.remainingAmount)"

        let expiry = UILabel()
        expiry.font = UIFont.sora(.regular, size: 12)
        expiry.textColor = UIColor.glassSecondaryText
        expiry.text = "期限: \(formattedDate(ms: allowance.policyExpiresAtMs))"

        let stack = UIStackView(arrangedSubviews: [title, remaining, expiry])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        chip.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: chip.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: chip.bottomAnchor, constant: -10)
        ])
        return chip
    }

    private func formattedDate(ms: UInt64) -> String {
        guard ms > 0 else { return "未設定" }
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func presentTopUpInfo() {
        let alert = PMAlertController(title: "トップアップ手順",
                                      description: "オフライン残高は発行者から配布される証明書で補充します。オンライン接続時にオペレーターへ申請し、証明書を受け取った後に「トップアップを取得」で同期してください。",
                                      image: nil,
                                      style: .alert)
        alert.addAction(PMAlertAction(title: "OK", style: .default, action: nil))
        present(alert, animated: true)
    }

    private func createVoucher() {
        let receiver = receiverField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !receiver.isEmpty else {
            presentError(message: "受取先のアカウントIDまたはエイリアスを入力してください。")
            return
        }
        let amountDecimal = Decimal(string: amountField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        guard let amount = amountDecimal else {
            presentError(message: "金額が無効です。")
            return
        }
        let mode: OfflineWalletCirculationMode = modeControl.selectedSegmentIndex == 0 ? .ledgerReconcilable : .offlineOnly
        do {
            let voucher = try manager.createVoucher(receiverId: receiver,
                                                    amount: amount,
                                                    note: noteField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                                                    mode: mode)
            currentVoucher = voucher
            renderVoucher(voucher)
        } catch {
            presentError(message: error.localizedDescription)
        }
    }

    private func renderVoucher(_ voucher: OfflinePaymentVoucher) {
        guard let payload = voucher.qrPayloadString else {
            presentError(message: OfflinePaymentError.invalidPayload.localizedDescription)
            return
        }
        qrImageView.image = createQRCode(message: payload, size: 6)
        voucherInfoLabel.text = """
        \(manager.formattedAmount(Decimal(string: voucher.amount) ?? .zero)) を \(voucher.receiverId) に送信します。
        証明書: \(voucher.certificateIdHex)
        """
        pendingNdefPayload = payload
    }

    private func presentShareSheet() {
        guard let voucher = currentVoucher,
              let payload = voucher.qrPayloadString else {
            presentError(message: "共有できるバウチャーがありません。")
            return
        }
        let controller = UIActivityViewController(activityItems: [payload], applicationActivities: nil)
        controller.popoverPresentationController?.sourceView = shareButton
        present(controller, animated: true)
    }

    private func handleClipboardImport() {
        let pasted = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !pasted.isEmpty else {
            presentError(message: "クリップボードにバウチャーがありません。")
            return
        }
        voucherPayloadView.text = pasted
        handleImportedPayload(pasted)
    }

    private func handleImportedPayload(_ payload: String) {
        do {
            let voucher = try manager.validateVoucherPayload(payload)
            importedVoucher = voucher
            receiveInfoLabel.text = """
            送信者: \(voucher.senderId)
            金額: \(manager.formattedAmount(Decimal(string: voucher.amount) ?? .zero))
            メモ: \(voucher.note ?? "なし")
            """
            redeemButton.isEnabled = true
            redeemButton.alpha = 1
        } catch {
            importedVoucher = nil
            redeemButton.isEnabled = false
            redeemButton.alpha = 0.6
            receiveInfoLabel.text = "読み取りに失敗しました。もう一度お試しください。"
            presentError(message: error.localizedDescription)
        }
    }

    private func redeemImportedVoucher() {
        guard let voucher = importedVoucher else {
            presentError(message: "取り込めるバウチャーがありません。")
            return
        }
        if manager.isVoucherRedeemed(voucher) {
            presentError(message: OfflinePaymentError.alreadyRedeemed.localizedDescription)
            return
        }
        manager.markVoucherRedeemed(voucher)
        receiveInfoLabel.text = "取り込み済みとしてマークしました。オンラインに戻ったら台帳へ提出してください。"
        redeemButton.isEnabled = false
        redeemButton.alpha = 0.6
        updateReconciliationInfo()
        renderRedeemedList()
    }

    private func writeNFC() {
#if canImport(CoreNFC) && !targetEnvironment(simulator)
        guard let payload = pendingNdefPayload,
              let data = payload.data(using: .utf8) else {
            presentError(message: "NFCに送信するデータがありません。")
            return
        }
        guard NFCNDEFReaderSession.readingAvailable else {
            presentError(message: "このデバイスはNFC書き込みに対応していません。")
            return
        }
        pendingNdefPayload = payload
        nfcSession = NFCNDEFReaderSession(delegate: self,
                                          queue: nil,
                                          invalidateAfterFirstRead: false)
        nfcSession?.alertMessage = "NFCタグにかざしてオフラインバウチャーを書き込みます。"
        nfcSession?.begin()
#else
        presentError(message: "このデバイスはNFCをサポートしていません。")
#endif
    }

    private func presentScanner() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            showScanner()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    granted ? self?.showScanner() : self?.presentError(message: "カメラへのアクセスが必要です。")
                }
            }
        default:
            presentError(message: "設定からカメラアクセスを許可してください。")
        }
    }

    private func showScanner() {
        let scanner = OfflineVoucherScannerViewController()
        scanner.delegate = self
        scanner.modalPresentationStyle = .fullScreen
        present(scanner, animated: true)
    }

    private func updateReconciliationInfo() {
        let total = manager.redeemedTotal
        let count = manager.redeemedVouchers().count
        if count == 0 {
            reconciliationInfoLabel.text = "オンライン残高へ戻すバウチャーはありません。"
            reconcileButton.isEnabled = false
            reconcileButton.alpha = 0.6
        } else {
            reconciliationInfoLabel.text = "取り込み済み: \(count) 件 / 合計 \(manager.formattedAmount(total))"
            reconcileButton.isEnabled = true
            reconcileButton.alpha = 1
        }
    }

    private func refreshServerTransfers() async {
        serverTransfersButton.isEnabled = false
        defer { serverTransfersButton.isEnabled = true }
        do {
            let accountId = KeychainManager.instance.accountId
            let list = try await manager.fetchRemoteTransfers(limit: 5, depositAccountId: accountId)
            let headline = "Toriiキュー: \(list.total) 件"
            if list.items.isEmpty {
                serverTransfersLabel.text = "\(headline) / 新しいオフライン転送はありません。"
                return
            }
            let previews = list.items.prefix(2).map { item in
                let amount = item.totalAmount
                return "\(item.bundleIdHex.prefix(8))… \(amount) -> \(item.depositAccountId)"
            }.joined(separator: "\n")
            serverTransfersLabel.text = "\(headline)\n\(previews)"
        } catch {
            serverTransfersLabel.text = "Toriiキューの取得に失敗: \(error.localizedDescription)"
        }
    }

    private func presentReconcileOptions() {
        let description: String
        if manager.hasOnlineSubmitter && !manager.isMockSubmission {
            description = "取り込み済みバウチャーをオンラインへ戻します。"
        } else if manager.hasOnlineSubmitter {
            description = "オンライン送信フロー（モック）で残高に戻します。"
        } else {
            description = "取り込み済みバウチャーをどう扱いますか？（現在はモック転送）"
        }

        let alert = PMAlertController(title: "オフライン残高をオンラインへ",
                                      description: description,
                                      image: nil,
                                      style: .alert)
        alert.addAction(PMAlertAction(title: "JSONで共有", style: .default) { [weak self] in
            self?.shareRedeemedBundle()
        })
        let returnTitle: String
        if manager.hasOnlineSubmitter && manager.isMockSubmission {
            returnTitle = "オンライン残高に戻す（モック送信）"
        } else if manager.hasOnlineSubmitter {
            returnTitle = "オンライン残高に戻す"
        } else {
            returnTitle = "オンライン残高に戻す（モック）"
        }
        alert.addAction(PMAlertAction(title: returnTitle, style: .default) { [weak self] in
            self?.performReturnToOnline()
        })
        alert.addAction(PMAlertAction(title: "キャンセル", style: .cancel, action: nil))
        present(alert, animated: true)
    }

    private func shareRedeemedBundle() {
        guard let payload = manager.exportRedeemedJSON() else {
            presentError(message: "転送できるバウチャーがありません。")
            return
        }
        let controller = UIActivityViewController(activityItems: [payload], applicationActivities: nil)
        controller.popoverPresentationController?.sourceView = reconcileButton
        present(controller, animated: true)
    }

    private func performReturnToOnline() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let receipt = try await manager.transferRedeemedToOnline()
                updateReconciliationInfo()
                renderRedeemedList()
                let context: String
                if manager.hasOnlineSubmitter && !manager.isMockSubmission {
                    context = "オンライン残高に送信しました。"
                } else if manager.hasOnlineSubmitter {
                    context = "オンライン送信パイプライン（モック）を実行しました。"
                } else {
                    context = "モック転送を完了しました。"
                }
                let message = """
                \(receipt.voucherCount) 件のバウチャーをオンライン残高へ戻しました。
                合計: \(manager.formattedAmount(receipt.movedAmount))
                \(context)
                """
                let alert = PMAlertController(title: "転送完了", description: message, image: nil, style: .alert)
                alert.addAction(PMAlertAction(title: "OK", style: .default, action: nil))
                present(alert, animated: true)
            } catch {
                await MainActor.run {
                    self.presentError(message: error.localizedDescription)
                }
            }
        }
    }

    private func renderRedeemedList() {
        redeemedListStack.arrangedSubviews.forEach { view in
            redeemedListStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        let vouchers = manager.redeemedVouchers()
        guard !vouchers.isEmpty else {
            let label = UILabel()
            label.text = "取り込み済みのバウチャーはありません。"
            label.font = UIFont.sora(.regular, size: 12)
            label.textColor = UIColor.glassSecondaryText
            redeemedListStack.addArrangedSubview(label)
            return
        }
        vouchers.prefix(5).forEach { voucher in
            let card = UIView()
            card.backgroundColor = UIColor.glassFieldBackground.withAlphaComponent(0.9)
            card.layer.cornerRadius = 10

            let receiver = UILabel()
            receiver.font = UIFont.sora(.semiBold, size: 13)
            receiver.textColor = UIColor.glassPrimaryText
            receiver.text = voucher.receiverId

            let amount = UILabel()
            amount.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .medium)
            amount.textColor = UIColor.glassSecondaryText
            amount.text = manager.formattedAmount(Decimal(string: voucher.amount) ?? .zero)

            let idLabel = UILabel()
            idLabel.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            idLabel.textColor = UIColor.glassSecondaryText
            idLabel.text = "証明書: \(voucher.certificateIdHex.prefix(10))..."

            let copyButton = UIButton(type: .system)
            copyButton.setImage(UIImage(systemName: "doc.on.doc"), for: .normal)
            copyButton.tintColor = UIColor.glassPrimaryText
            copyButton.addAction(UIAction { _ in
                UIPasteboard.general.string = voucher.qrPayloadString
            }, for: .touchUpInside)
            copyButton.translatesAutoresizingMaskIntoConstraints = false
            copyButton.widthAnchor.constraint(equalToConstant: 30).isActive = true

            let vstack = UIStackView(arrangedSubviews: [receiver, amount, idLabel])
            vstack.axis = .vertical
            vstack.spacing = 2

            let row = UIStackView(arrangedSubviews: [vstack, copyButton])
            row.axis = .horizontal
            row.alignment = .center
            row.spacing = 6
            row.translatesAutoresizingMaskIntoConstraints = false

            card.addSubview(row)
            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
                row.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
                row.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
                row.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8)
            ])
            redeemedListStack.addArrangedSubview(card)
        }
        if vouchers.count > 5 {
            let more = UILabel()
            more.text = "+\(vouchers.count - 5) 件 さらにあります。"
            more.font = UIFont.sora(.regular, size: 12)
            more.textColor = UIColor.glassSecondaryText
            redeemedListStack.addArrangedSubview(more)
        }
    }

    private func clearRedeemedHistory() {
        manager.clearRedeemed()
        updateReconciliationInfo()
        renderRedeemedList()
    }

    // MARK: - Alerts

    private func presentError(message: String) {
        let alert = PMAlertController(title: "オフライン決済", description: message, image: nil, style: .alert)
        alert.addAction(PMAlertAction(title: "OK", style: .cancel, action: nil))
        present(alert, animated: true)
    }
}

#if canImport(CoreNFC) && !targetEnvironment(simulator)
extension OfflinePaymentsViewController: NFCNDEFReaderSessionDelegate {
    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        nfcSession = nil
        if let readerError = error as? NFCReaderError,
           readerError.code == .readerSessionInvalidationErrorFirstNDEFTagRead {
            return
        }
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        guard let payload = pendingNdefPayload,
              let data = payload.data(using: .utf8) else {
            session.invalidate(errorMessage: "データが見つかりませんでした。")
            return
        }
        let message = NFCNDEFMessage(records: [
            NFCNDEFPayload(format: .media,
                           type: "application/json".data(using: .utf8) ?? Data(),
                           identifier: Data(),
                           payload: data)
        ])
        guard let tag = tags.first else {
            session.invalidate(errorMessage: "タグが見つかりませんでした。")
            return
        }
        session.connect(to: tag) { [weak self] maybeError in
            if let maybeError {
                session.invalidate(errorMessage: "NFC接続に失敗しました: \(maybeError.localizedDescription)")
                return
            }
            tag.queryNDEFStatus { status, _, statusError in
                if let statusError {
                    session.invalidate(errorMessage: statusError.localizedDescription)
                    return
                }
                guard status == .readWrite else {
                    session.invalidate(errorMessage: "NFCタグに書き込めませんでした。")
                    return
                }
                tag.writeNDEF(message) { writeError in
                    if let writeError {
                        session.invalidate(errorMessage: writeError.localizedDescription)
                        return
                    }
                    session.alertMessage = "バウチャーを書き込みました。"
                    session.invalidate()
                    self?.nfcSession = nil
                }
            }
        }
    }
}
#endif

enum SubscriptionCadence: String, Codable, CaseIterable {
    case monthly
    case quarterly
    case yearly

    var title: String {
        switch self {
        case .monthly: return "月次"
        case .quarterly: return "四半期"
        case .yearly: return "年次"
        }
    }

    var months: Int {
        switch self {
        case .monthly: return 1
        case .quarterly: return 3
        case .yearly: return 12
        }
    }
}

enum SubscriptionStatus: String, Codable {
    case active
    case paused
    case canceled

    var title: String {
        switch self {
        case .active: return "有効"
        case .paused: return "一時停止"
        case .canceled: return "解約済み"
        }
    }
}

enum SubscriptionAmountType: String, Codable {
    case fixed
    case variable
}

struct SubscriptionRecord: Codable, Identifiable {
    let id: UUID
    var merchantName: String
    var amount: Decimal?
    var maxAmount: Decimal?
    var amountType: SubscriptionAmountType
    var cadence: SubscriptionCadence
    var nextPaymentDate: Date
    var status: SubscriptionStatus
    var cancelAtPeriodEnd: Bool
    var lastChargeDate: Date?
    var lastChargeAmount: Decimal?
    var note: String?

    func displayAmountLabel(unit: String) -> String {
        SubscriptionAmountFormatter.label(amount: amount,
                                          maxAmount: maxAmount,
                                          type: amountType,
                                          unit: unit)
    }

    var statusLabel: String {
        if cancelAtPeriodEnd, status == .active {
            return "解約予定"
        }
        return status.title
    }
}

enum SubscriptionSchedule {
    static func advance(from date: Date, cadence: SubscriptionCadence) -> Date {
        Calendar.current.date(byAdding: .month, value: cadence.months, to: date) ?? date
    }
}

enum SubscriptionBilling {
    static func applyAutoDeductions(_ records: inout [SubscriptionRecord], now: Date = Date()) -> Bool {
        var changed = false
        for index in records.indices {
            var record = records[index]
            guard record.status == .active else { continue }
            var guardCount = 0
            while record.nextPaymentDate <= now && guardCount < 24 {
                record.lastChargeDate = record.nextPaymentDate
                record.lastChargeAmount = chargeAmount(for: record, on: record.nextPaymentDate)
                if record.cancelAtPeriodEnd {
                    record.status = .canceled
                    record.cancelAtPeriodEnd = false
                    changed = true
                    break
                }
                record.nextPaymentDate = SubscriptionSchedule.advance(from: record.nextPaymentDate,
                                                                     cadence: record.cadence)
                changed = true
                guardCount += 1
            }
            records[index] = record
        }
        return changed
    }

    private static func chargeAmount(for record: SubscriptionRecord, on date: Date) -> Decimal? {
        switch record.amountType {
        case .fixed:
            return record.amount ?? .zero
        case .variable:
            guard let maxAmount = record.maxAmount else { return nil }
            let percent = Decimal(usagePercent(for: record.id, date: date))
            let maxNumber = NSDecimalNumber(decimal: maxAmount)
            let percentNumber = NSDecimalNumber(decimal: percent)
                .dividing(by: NSDecimalNumber(value: 100))
            let raw = maxNumber.multiplying(by: percentNumber)
            let handler = NSDecimalNumberHandler(roundingMode: .plain,
                                                 scale: 2,
                                                 raiseOnExactness: false,
                                                 raiseOnOverflow: false,
                                                 raiseOnUnderflow: false,
                                                 raiseOnDivideByZero: false)
            return raw.rounding(accordingToBehavior: handler).decimalValue
        }
    }

    private static func usagePercent(for id: UUID, date: Date) -> Int {
        let month = Calendar.current.component(.month, from: date)
        let year = Calendar.current.component(.year, from: date)
        let scalarSum = id.uuidString.unicodeScalars.reduce(0) { partial, scalar in
            partial + Int(scalar.value)
        }
        let seed = abs(scalarSum + month * 31 + year * 17)
        return 40 + (seed % 60)
    }
}

enum SubscriptionAmountFormatter {
    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    static func label(amount: Decimal?,
                      maxAmount: Decimal?,
                      type: SubscriptionAmountType,
                      unit: String) -> String {
        switch type {
        case .fixed:
            return "\(unit) \(format(amount) ?? "--")"
        case .variable:
            if let maxLabel = format(maxAmount) {
                return "上限 \(unit) \(maxLabel)"
            }
            return "変動"
        }
    }

    private static func format(_ value: Decimal?) -> String? {
        guard let value else { return nil }
        return formatter.string(from: value as NSDecimalNumber)
    }
}

final class SubscriptionStore {
    private let store: UserDefaults
    private let key = "subscriptionHub.records"

    init(store: UserDefaults = .standard) {
        self.store = store
    }

    func load() -> [SubscriptionRecord] {
        if let data = store.data(forKey: key),
           let decoded = try? decoder.decode([SubscriptionRecord].self, from: data) {
            return decoded
        }
        let seeded = SubscriptionStore.seededRecords
        save(seeded)
        return seeded
    }

    func save(_ records: [SubscriptionRecord]) {
        guard let data = try? encoder.encode(records) else { return }
        store.setValue(data, forKey: key)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static let seededRecords: [SubscriptionRecord] = {
        let now = Date()
        return [
            SubscriptionRecord(
                id: UUID(),
                merchantName: "Netflix",
                amount: Decimal(string: "1500"),
                maxAmount: nil,
                amountType: .fixed,
                cadence: .monthly,
                nextPaymentDate: SubscriptionSchedule.advance(from: now, cadence: .monthly),
                status: .active,
                cancelAtPeriodEnd: false,
                lastChargeDate: nil,
                lastChargeAmount: nil,
                note: "Streaming"
            ),
            SubscriptionRecord(
                id: UUID(),
                merchantName: "AWS",
                amount: nil,
                maxAmount: Decimal(string: "9000"),
                amountType: .variable,
                cadence: .monthly,
                nextPaymentDate: SubscriptionSchedule.advance(from: now, cadence: .monthly),
                status: .active,
                cancelAtPeriodEnd: false,
                lastChargeDate: nil,
                lastChargeAmount: nil,
                note: "Usage based"
            ),
            SubscriptionRecord(
                id: UUID(),
                merchantName: "Duolingo",
                amount: Decimal(string: "1200"),
                maxAmount: nil,
                amountType: .fixed,
                cadence: .yearly,
                nextPaymentDate: SubscriptionSchedule.advance(from: now, cadence: .yearly),
                status: .paused,
                cancelAtPeriodEnd: false,
                lastChargeDate: nil,
                lastChargeAmount: nil,
                note: nil
            )
        ]
    }()
}

@MainActor
enum SubscriptionHubConfigurator {
    static func configureIfNeeded(_ controller: UIViewController) {
        guard let tabController = controller as? UITabBarController else { return }
        let alreadyAdded = tabController.viewControllers?.contains(where: { entry in
            if let nav = entry as? UINavigationController {
                return nav.viewControllers.first is SubscriptionHubViewController
            }
            return entry is SubscriptionHubViewController
        }) ?? false
        guard !alreadyAdded else { return }

        let hub = SubscriptionHubViewController()
        let nav = UINavigationController(rootViewController: hub)
        let icon = UIImage(systemName: "repeat")
        nav.tabBarItem = UITabBarItem(title: "Subscriptions", image: icon, selectedImage: icon)

        var controllers = tabController.viewControllers ?? []
        let insertIndex = min(2, controllers.count)
        controllers.insert(nav, at: insertIndex)
        tabController.viewControllers = controllers
    }
}

@MainActor
final class SubscriptionHubViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let store = SubscriptionStore()
    private var subscriptions: [SubscriptionRecord] = []
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let summaryCard = UIView()
    private let summaryTitle = UILabel()
    private let summaryDetail = UILabel()
    private let nextDueLabel = UILabel()
    private let unitLabel = ToriiConfiguration.load().unit

    override func viewDidLoad() {
        super.viewDidLoad()
        installGlassBackground()
        view.backgroundColor = .clear
        configureNavigation()
        configureSummaryCard()
        configureTableView()
        subscriptions = store.load()
        applyAutoDeductionsIfNeeded()
        updateSummary()
        applySoraFonts()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.tintColor = UIColor.label
        navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor.label]
        navigationController?.topViewController?.navigationItem.title = "Subscription Hub"
        tabBarController?.tabBar.isHidden = false
        applyAutoDeductionsIfNeeded()
        updateSummary()
        tableView.reloadData()
    }

    private func configureNavigation() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add,
                                                            target: self,
                                                            action: #selector(addSubscription))
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "person.crop.circle"),
                                                           style: .plain,
                                                           target: self,
                                                           action: #selector(showAccountSwitcher))
    }

    private func configureSummaryCard() {
        summaryCard.translatesAutoresizingMaskIntoConstraints = false
        summaryCard.applyGlassCardStyle(cornerRadius: 22)
        view.addSubview(summaryCard)

        let stack = UIStackView(arrangedSubviews: [summaryTitle, summaryDetail, nextDueLabel])
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        summaryCard.addSubview(stack)

        summaryTitle.font = UIFont.sora(.semiBold, size: 16)
        summaryTitle.textColor = UIColor.glassPrimaryText
        summaryTitle.text = "Subscriptions"

        summaryDetail.font = UIFont.sora(.regular, size: 13)
        summaryDetail.textColor = UIColor.glassSecondaryText
        summaryDetail.numberOfLines = 0

        nextDueLabel.font = UIFont.sora(.medium, size: 13)
        nextDueLabel.textColor = UIColor.glassSecondaryText
        nextDueLabel.numberOfLines = 0

        NSLayoutConstraint.activate([
            summaryCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            summaryCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            summaryCard.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: summaryCard.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: summaryCard.trailingAnchor),
            stack.topAnchor.constraint(equalTo: summaryCard.topAnchor),
            stack.bottomAnchor.constraint(equalTo: summaryCard.bottomAnchor)
        ])
    }

    private func configureTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(SubscriptionCell.self, forCellReuseIdentifier: SubscriptionCell.reuseId)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: summaryCard.bottomAnchor, constant: 12),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func updateSummary() {
        let active = subscriptions.filter { $0.status == .active }.count
        let paused = subscriptions.filter { $0.status == .paused }.count
        let canceled = subscriptions.filter { $0.status == .canceled }.count
        summaryDetail.text = "有効 \(active) / 一時停止 \(paused) / 解約 \(canceled)"

        let upcoming = subscriptions
            .filter { $0.status == .active }
            .sorted { $0.nextPaymentDate < $1.nextPaymentDate }
            .first
        if let upcoming {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            nextDueLabel.text = "次回: \(upcoming.merchantName) \(formatter.string(from: upcoming.nextPaymentDate))"
        } else {
            nextDueLabel.text = "次回: 予定なし"
        }
    }

    private func persist() {
        store.save(subscriptions)
        updateSummary()
        tableView.reloadData()
    }

    private func applyAutoDeductionsIfNeeded() {
        if SubscriptionBilling.applyAutoDeductions(&subscriptions) {
            store.save(subscriptions)
        }
    }

    @objc private func addSubscription() {
        let alert = UIAlertController(title: "サブスクリプション追加",
                                      message: "サービス名と金額を入力してください。",
                                      preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "サービス名"
        }
        alert.addTextField { field in
            field.placeholder = "金額 (\(self.unitLabel))"
            field.keyboardType = .decimalPad
        }
        alert.addTextField { field in
            field.placeholder = "上限 (任意)"
            field.keyboardType = .decimalPad
        }
        alert.addAction(UIAlertAction(title: "キャンセル", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "追加", style: .default) { [weak self] _ in
            guard let self else { return }
            let name = alert.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { return }
            let amountText = alert.textFields?[1].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let maxText = alert.textFields?[2].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let amount = Decimal(string: amountText)
            let maxAmount = Decimal(string: maxText)
            let amountType: SubscriptionAmountType = amount != nil ? .fixed : .variable
            let record = SubscriptionRecord(
                id: UUID(),
                merchantName: name,
                amount: amount,
                maxAmount: maxAmount,
                amountType: amountType,
                cadence: .monthly,
                nextPaymentDate: SubscriptionSchedule.advance(from: Date(), cadence: .monthly),
                status: .active,
                cancelAtPeriodEnd: false,
                lastChargeDate: nil,
                lastChargeAmount: nil,
                note: nil
            )
            self.subscriptions.insert(record, at: 0)
            self.persist()
        })
        present(alert, animated: true)
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

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        subscriptions.count
    }

    func tableView(_ tableView: UITableView,
                   cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: SubscriptionCell.reuseId,
                                                       for: indexPath) as? SubscriptionCell else {
            return UITableViewCell()
        }
        cell.configure(with: subscriptions[indexPath.row], unit: unitLabel)
        return cell
    }

    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        var actions: [UIContextualAction] = []
        let record = subscriptions[indexPath.row]

        if record.status != .canceled {
            let pauseTitle = record.status == .active ? "停止" : "再開"
            let pause = UIContextualAction(style: .normal, title: pauseTitle) { [weak self] _, _, completion in
                guard let self else { return }
                var updated = subscriptions[indexPath.row]
                updated.status = updated.status == .active ? .paused : .active
                subscriptions[indexPath.row] = updated
                persist()
                completion(true)
            }
            pause.backgroundColor = UIColor.systemOrange
            actions.append(pause)

            let cancelTitle = record.cancelAtPeriodEnd ? "継続" : "期末終了"
            let cancel = UIContextualAction(style: .normal, title: cancelTitle) { [weak self] _, _, completion in
                guard let self else { return }
                var updated = subscriptions[indexPath.row]
                updated.cancelAtPeriodEnd.toggle()
                subscriptions[indexPath.row] = updated
                persist()
                completion(true)
            }
            cancel.backgroundColor = UIColor.systemIndigo
            actions.append(cancel)
        }

        let remove = UIContextualAction(style: .destructive, title: "削除") { [weak self] _, _, completion in
            guard let self else { return }
            subscriptions.remove(at: indexPath.row)
            persist()
            completion(true)
        }
        actions.append(remove)

        let config = UISwipeActionsConfiguration(actions: actions)
        config.performsFirstActionWithFullSwipe = false
        return config
    }
}

final class SubscriptionCell: UITableViewCell {
    static let reuseId = "SubscriptionCell"

    private let cardView = UIView()
    private let titleLabel = UILabel()
    private let amountLabel = UILabel()
    private let detailLabel = UILabel()
    private let statusLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        configureLayout()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        configureLayout()
    }

    private func configureLayout() {
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.applyGlassCardStyle(cornerRadius: 20)
        contentView.addSubview(cardView)

        let topStack = UIStackView(arrangedSubviews: [titleLabel, statusLabel])
        topStack.axis = .horizontal
        topStack.spacing = 8
        topStack.alignment = .center
        topStack.distribution = .equalSpacing

        let infoStack = UIStackView(arrangedSubviews: [amountLabel, detailLabel])
        infoStack.axis = .vertical
        infoStack.spacing = 4

        let mainStack = UIStackView(arrangedSubviews: [topStack, infoStack])
        mainStack.axis = .vertical
        mainStack.spacing = 8
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.isLayoutMarginsRelativeArrangement = true
        mainStack.layoutMargins = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        cardView.addSubview(mainStack)

        titleLabel.font = UIFont.sora(.bold, size: 16)
        titleLabel.textColor = UIColor.glassPrimaryText

        amountLabel.font = UIFont.sora(.semiBold, size: 14)
        amountLabel.textColor = UIColor.glassPrimaryText

        detailLabel.font = UIFont.sora(.regular, size: 13)
        detailLabel.textColor = UIColor.glassSecondaryText
        detailLabel.numberOfLines = 0

        statusLabel.font = UIFont.sora(.semiBold, size: 12)
        statusLabel.textColor = UIColor.white
        statusLabel.backgroundColor = UIColor.systemGreen
        statusLabel.layer.cornerRadius = 10
        statusLabel.layer.masksToBounds = true
        statusLabel.textAlignment = .center
        statusLabel.setContentHuggingPriority(.required, for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        statusLabel.enforceHeight(20)

        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),

            mainStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            mainStack.topAnchor.constraint(equalTo: cardView.topAnchor),
            mainStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),

            statusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 72)
        ])
    }

    func configure(with record: SubscriptionRecord, unit: String) {
        titleLabel.text = record.merchantName
        amountLabel.text = record.displayAmountLabel(unit: unit)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        var detail = "次回 \(formatter.string(from: record.nextPaymentDate)) ・ \(record.cadence.title)"
        if let lastDate = record.lastChargeDate, let lastAmount = record.lastChargeAmount {
            let lastLabel = SubscriptionAmountFormatter.label(amount: lastAmount,
                                                              maxAmount: nil,
                                                              type: .fixed,
                                                              unit: unit)
            detail += "\n前回 \(lastLabel) \(formatter.string(from: lastDate))"
        }
        if let note = record.note, !note.isEmpty {
            detail += "\n\(note)"
        }
        detailLabel.text = detail
        statusLabel.text = " \(record.statusLabel) "

        switch record.status {
        case .active:
            statusLabel.backgroundColor = record.cancelAtPeriodEnd ? UIColor.systemOrange : UIColor.systemGreen
        case .paused:
            statusLabel.backgroundColor = UIColor.systemGray
        case .canceled:
            statusLabel.backgroundColor = UIColor.systemRed
        }
    }
}
