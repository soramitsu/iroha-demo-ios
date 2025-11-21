import UIKit
import PMAlertController
import IrohaSwift

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
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "paintbrush"),
                                                            style: .plain,
                                                            target: self,
                                                            action: #selector(showThemeSettings))
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

    private func loadSnapshot(showLoader: Bool = true) {
        guard let accountId = KeychainManager.instance.accountId else {
            presentRegistrationReset()
            return
        }

        var alert: PMAlertController?
        if showLoader {
            alert = PMAlertController(title: "通信中", description: "ウォレットを更新しています", image: nil, style: .alert)
            if let alert { present(alert, animated: true) }
        }

        Task {
            do {
                let snapshot = try await ToriiService.shared.fetchSnapshot(accountId: accountId)
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
                await MainActor.run {
                    alert?.dismiss(animated: true)
                    self.historyRefresh.endRefreshing()
                    self.presentError(message: error.localizedDescription)
                }
            }
        }
    }

    private func formatted(amount: Decimal) -> String {
        "\(amount.plainString) \(config.unit)"
    }

    private func presentError(message: String) {
        let alert = PMAlertController(title: "エラー", description: message, image: nil, style: .alert)
        alert.addAction(PMAlertAction(title: "OK", style: .cancel, action: nil))
        present(alert, animated: true)
    }

    private func presentRegistrationReset() {
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

    private func navigateToRegister() {
        let storyboard = storyboard ?? UIStoryboard(name: "Main", bundle: nil)
        if let register = storyboard.instantiateViewController(withIdentifier: "Register") as UIViewController? {
            present(register, animated: true)
        }
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

        if let accountId = KeychainManager.instance.accountId {
            let accountRow = UIStackView()
            accountRow.axis = .horizontal
            accountRow.alignment = .center
            accountRow.spacing = 10
            let accountLabel = UILabel()
            accountLabel.font = UIFont.sora(.medium, size: 13)
            accountLabel.adjustsFontForContentSizeCategory = true
            accountLabel.textColor = UIColor.glassSecondaryText
            accountLabel.numberOfLines = 0
            accountLabel.text = accountId
            accountRow.addArrangedSubview(accountLabel)

            let copyButton = UIButton(type: .system)
            copyButton.setImage(UIImage(systemName: "doc.on.doc"), for: .normal)
            copyButton.tintColor = UIColor.glassPrimaryText
            copyButton.backgroundColor = UIColor.glassFieldBackground
            copyButton.layer.cornerRadius = 12
            copyButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
            copyButton.setContentHuggingPriority(.required, for: .horizontal)
            let copyAction = UIAction { [weak self] _ in
                UIPasteboard.general.string = accountId
                let haptic = UIImpactFeedbackGenerator(style: .light)
                haptic.impactOccurred()
                UIAccessibility.post(notification: .announcement, argument: "Account ID copied")
            }
            copyButton.addAction(copyAction, for: .touchUpInside)
            accountRow.addArrangedSubview(copyButton)
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
        sendButton.contentEdgeInsets = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        sendButton.enforceHeight(52)
        sendButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: -6, bottom: 0, right: 6)
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
        receiveButton.contentEdgeInsets = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        receiveButton.enforceHeight(52)
        receiveButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: -6, bottom: 0, right: 6)
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
        actionsRow.addArrangedSubview(sendButton)
        actionsRow.addArrangedSubview(receiveButton)
        stack.setCustomSpacing(18, after: balanceLabel)
        stack.addArrangedSubview(actionsRow)

        container.layoutIfNeeded()
        sendButton.refreshGlassButtonStyleLayout()
        receiveButton.refreshGlassButtonStyleLayout()

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
