import UIKit
import TextFieldEffects
import PMAlertController
import Toast_Swift
import IrohaSwift

@MainActor
final class SoraNexusOnboardingViewController: UIViewController {
    private let service = ToriiService.shared
    private let backupStorage = KeyBackupStorage.shared
    private var generatedMaterial: SoraNexusKeyMaterial?
    private var selectedBackups = Set<KeyBackupDestination>()

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let displayNameField = HoshiTextField(frame: .zero)
    private let wordCountControl = UISegmentedControl(items: ["12語", "24語"])
    private let generateButton = UIButton(type: .system)
    private let mnemonicCard = UIView()
    private let mnemonicLabel = UILabel()
    private let manualBackupButton = UIButton(type: .system)
    private let iCloudBackupButton = UIButton(type: .system)
    private let googleBackupButton = UIButton(type: .system)
    private let connectButton = UIButton(type: .system)
    private let startButton = UIButton(type: .system)
    private let appearanceButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let activityOverlay = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let activityIndicator = UIActivityIndicatorView(style: .large)

    override func viewDidLoad() {
        super.viewDidLoad()
        configureLayout()
        configureButtons()
        installGlassBackground()
        IrohaConnectCoordinator.shared.delegate = self
        applySoraFonts()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        [generateButton, manualBackupButton, iCloudBackupButton, googleBackupButton, connectButton, startButton, appearanceButton].forEach {
            $0.refreshGlassButtonStyleLayout()
        }
    }

    private func configureLayout() {
        view.backgroundColor = .black
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        scrollView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 60, right: 0)
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        contentStack.axis = .vertical
        contentStack.spacing = 24
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -24),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 32),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -48)
        ])

        titleLabel.text = "SORA Nexus"
        titleLabel.font = UIFont.sora(.bold, size: 34)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = UIColor.glassPrimaryText

        subtitleLabel.text = "初回起動では鍵を生成するか、IrohaConnectで既存アカウントを連携できます。"
        subtitleLabel.font = UIFont.sora(.regular, size: 16)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textColor = UIColor.glassSecondaryText
        subtitleLabel.numberOfLines = 0

        displayNameField.placeholder = "表示名"
        displayNameField.translatesAutoresizingMaskIntoConstraints = false
        displayNameField.enforceHeight(56)
        displayNameField.keyboardType = .default
        displayNameField.autocapitalizationType = .none
        displayNameField.autocorrectionType = .no
        displayNameField.applyGlassInputStyle()

        wordCountControl.selectedSegmentIndex = 0
        wordCountControl.selectedSegmentTintColor = .iroha
        wordCountControl.backgroundColor = UIColor.glassFieldBackground
        wordCountControl.layer.cornerRadius = 18
        wordCountControl.layer.masksToBounds = true
        wordCountControl.enforceHeight(36)
        let normalWordAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.glassSecondaryText,
            .font: UIFont.sora(.regular, size: 13)
        ]
        let selectedWordAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.glassPrimaryText,
            .font: UIFont.sora(.semiBold, size: 13)
        ]
        wordCountControl.setTitleTextAttributes(normalWordAttributes, for: .normal)
        wordCountControl.setTitleTextAttributes(selectedWordAttributes, for: .selected)

        generateButton.setTitle("SORA Nexus鍵を生成", for: .normal)
        generateButton.addTarget(self, action: #selector(generateKeys), for: .touchUpInside)

        mnemonicCard.translatesAutoresizingMaskIntoConstraints = false
        mnemonicCard.applyGlassCardStyle(cornerRadius: 24)
        mnemonicLabel.text = "12/24語のパスフレーズがここに表示されます"
        mnemonicLabel.textColor = UIColor.glassPrimaryText
        mnemonicLabel.font = .monospacedSystemFont(ofSize: 16, weight: .medium)
        mnemonicLabel.numberOfLines = 0
        mnemonicLabel.adjustsFontForContentSizeCategory = true
        mnemonicLabel.translatesAutoresizingMaskIntoConstraints = false
        mnemonicCard.addSubview(mnemonicLabel)
        NSLayoutConstraint.activate([
            mnemonicLabel.leadingAnchor.constraint(equalTo: mnemonicCard.leadingAnchor, constant: 20),
            mnemonicLabel.trailingAnchor.constraint(equalTo: mnemonicCard.trailingAnchor, constant: -20),
            mnemonicLabel.topAnchor.constraint(equalTo: mnemonicCard.topAnchor, constant: 16),
            mnemonicLabel.bottomAnchor.constraint(equalTo: mnemonicCard.bottomAnchor, constant: -16)
        ])

        manualBackupButton.setTitle("手動でバックアップ", for: .normal)
        manualBackupButton.addTarget(self, action: #selector(handleManualBackup), for: .touchUpInside)

        iCloudBackupButton.setTitle("iCloudに保存", for: .normal)
        iCloudBackupButton.addTarget(self, action: #selector(handleICloudBackup), for: .touchUpInside)

        googleBackupButton.setTitle("Google Secure Storageに保存", for: .normal)
        googleBackupButton.addTarget(self, action: #selector(handleGoogleBackup), for: .touchUpInside)

        statusLabel.text = "バックアップ先を選択してください"
        statusLabel.textColor = UIColor.glassSecondaryText
        statusLabel.font = UIFont.sora(.regular, size: 14)
        statusLabel.numberOfLines = 0

        connectButton.setTitle("IrohaConnectで連携", for: .normal)
        connectButton.addTarget(self, action: #selector(startIrohaConnect), for: .touchUpInside)

        startButton.setTitle("ウォレットを開始", for: .normal)
        startButton.addTarget(self, action: #selector(startWallet), for: .touchUpInside)
        startButton.isEnabled = false
        startButton.alpha = 0.6

        appearanceButton.setTitle("ライト / ダーク設定", for: .normal)
        appearanceButton.addTarget(self, action: #selector(showAppearanceSettings), for: .touchUpInside)

        [generateButton, manualBackupButton, iCloudBackupButton, googleBackupButton, connectButton, startButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.enforceHeight(52)
            $0.applyGlassButtonStyle()
        }
        appearanceButton.translatesAutoresizingMaskIntoConstraints = false
        appearanceButton.enforceHeight(48)
        appearanceButton.applyGlassButtonStyle()

        let backupStack = UIStackView(arrangedSubviews: [manualBackupButton, iCloudBackupButton, googleBackupButton])
        backupStack.axis = .vertical
        backupStack.spacing = 12

        let heroStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        heroStack.axis = .vertical
        heroStack.spacing = 8

        contentStack.addArrangedSubview(heroStack)

        let identitySection = makeSection(title: "1. 表示名を設定",
                                          subtitle: "ウォレットとQR受け取り画面に表示されます。",
                                          bodyViews: [displayNameField, wordCountControl, generateButton])
        contentStack.addArrangedSubview(identitySection)

        let backupSection = makeSection(title: "2. パスフレーズをバックアップ",
                                        subtitle: "最低でも1種類の安全なバックアップを保管してください。",
                                        bodyViews: [mnemonicCard, statusLabel, backupStack])
        contentStack.addArrangedSubview(backupSection)

        let connectSection = makeSection(title: "既存アカウントを使用",
                                         subtitle: "すでにSORA Nexusをお持ちの場合はIrohaConnect経由で読み込みます。",
                                         bodyViews: [connectButton])
        contentStack.addArrangedSubview(connectSection)

        let launchSection = makeSection(title: "3. ウォレットを開始",
                                        subtitle: "バックアップ後にSORA Nexusウォレットへ進みます。",
                                        bodyViews: [startButton])
        contentStack.addArrangedSubview(launchSection)

        let appearanceSection = makeSection(title: "表示モード",
                                            subtitle: "ライト・ダークどちらでもSORA Nexusの雰囲気を楽しめます。",
                                            bodyViews: [appearanceButton])
        contentStack.insertArrangedSubview(appearanceSection, at: 1)

        contentStack.setCustomSpacing(16, after: heroStack)
        contentStack.setCustomSpacing(24, after: appearanceSection)
        contentStack.setCustomSpacing(24, after: identitySection)
        contentStack.setCustomSpacing(24, after: backupSection)

        updateBackupStatus()

        activityOverlay.translatesAutoresizingMaskIntoConstraints = false
        activityOverlay.alpha = 0
        activityOverlay.contentView.addSubview(activityIndicator)
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: activityOverlay.contentView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: activityOverlay.contentView.centerYAnchor)
        ])
        view.addSubview(activityOverlay)
        NSLayoutConstraint.activate([
            activityOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            activityOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            activityOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            activityOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureButtons() {
        styleActionButton(manualBackupButton, symbolName: "square.and.pencil")
        styleActionButton(iCloudBackupButton, symbolName: "icloud.and.arrow.up")
        styleActionButton(googleBackupButton, symbolName: "lock.shield")
        styleActionButton(connectButton, symbolName: "dot.radiowaves.left.and.right")
        styleActionButton(startButton, symbolName: "play.fill")
        styleActionButton(generateButton, symbolName: "sparkles")
        styleActionButton(appearanceButton, symbolName: "paintbrush")
    }

    private func styleActionButton(_ button: UIButton, symbolName: String) {
        if #available(iOS 15.0, *) {
            button.configuration = nil
        }
        button.tintColor = .white
        button.setImage(UIImage(systemName: symbolName), for: .normal)
        button.semanticContentAttribute = .forceLeftToRight
        if #unavailable(iOS 15.0) {
            button.titleEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: -8)
            button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
        }
    }

    private func makeSection(title: String, subtitle: String?, bodyViews: [UIView]) -> UIView {
        let container = UIView()
        container.applyGlassCardStyle(cornerRadius: 28)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        let heading = UILabel()
        heading.text = title
        heading.font = UIFont.sora(.semiBold, size: 18)
        heading.textColor = UIColor.glassPrimaryText
        heading.adjustsFontForContentSizeCategory = true
        stack.addArrangedSubview(heading)

        if let subtitle {
            let subtitleLabel = UILabel()
            subtitleLabel.text = subtitle
            subtitleLabel.font = UIFont.sora(.regular, size: 14)
            subtitleLabel.textColor = UIColor.glassSecondaryText
            subtitleLabel.numberOfLines = 0
            subtitleLabel.adjustsFontForContentSizeCategory = true
            stack.addArrangedSubview(subtitleLabel)
        }

        bodyViews.forEach { stack.addArrangedSubview($0) }

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    private func selectedWordCount() -> MnemonicWordCount {
        wordCountControl.selectedSegmentIndex == 0 ? .twelve : .twentyFour
    }

    @objc private func showAppearanceSettings() {
        let controller = ThemeSettingsViewController()
        controller.modalPresentationStyle = .pageSheet
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(controller, animated: true)
    }

    @objc private func generateKeys() {
        let name = displayNameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else {
            presentAlert(title: "表示名を入力してください", message: "ウォレットに表示される名前を設定します。")
            return
        }
        do {
            let mnemonic = try MnemonicGenerator.shared.generate(wordCount: selectedWordCount())
            generatedMaterial = try SoraNexusKeyMaterial(mnemonic: mnemonic)
            mnemonicLabel.text = mnemonic.phrase
            mnemonicLabel.textColor = UIColor.glassPrimaryText
            selectedBackups.removeAll()
            KeychainManager.instance.backupDestinations = []
            updateBackupStatus()
            updateStartButtonState()
        } catch {
            presentAlert(title: "鍵生成エラー", message: error.localizedDescription)
        }
    }

    @objc private func handleManualBackup() {
        guard let material = generatedMaterial else {
            presentAlert(title: "先に鍵を生成してください", message: "パスフレーズを表示した後でバックアップできます。")
            return
        }
        let activity = UIActivityViewController(activityItems: [material.phrase], applicationActivities: nil)
        activity.completionWithItemsHandler = { [weak self] _, completed, _, _ in
            guard let self else { return }
            if completed {
                self.markBackup(.manual)
                self.view.makeToast("手動バックアップを記録しました", duration: 1.5, position: .center)
            }
        }
        present(activity, animated: true)
    }

    @objc private func handleICloudBackup() {
        guard let phrase = generatedMaterial?.phrase else {
            presentAlert(title: "バックアップできません", message: "鍵を生成してから実行してください")
            return
        }
        do {
            try backupStorage.store(passphrase: phrase, destination: .iCloud)
            markBackup(.iCloud)
            view.makeToast("iCloudに保存しました", duration: 1.5, position: .center)
        } catch {
            presentAlert(title: "iCloudエラー", message: error.localizedDescription)
        }
    }

    @objc private func handleGoogleBackup() {
        guard let phrase = generatedMaterial?.phrase else {
            presentAlert(title: "バックアップできません", message: "鍵を生成してから実行してください")
            return
        }
        do {
            try backupStorage.store(passphrase: phrase, destination: .googleSecureStorage)
            markBackup(.googleSecureStorage)
            view.makeToast("Google Secure Storageに保存しました", duration: 1.5, position: .center)
        } catch {
            presentAlert(title: "保存エラー", message: error.localizedDescription)
        }
    }

    @objc private func startIrohaConnect() {
        IrohaConnectCoordinator.shared.delegate = self
        IrohaConnectCoordinator.shared.beginConnection()
    }

    @objc private func startWallet() {
        guard let material = generatedMaterial else {
            presentAlert(title: "鍵を生成してください", message: "SORA Nexus鍵が必要です。")
            return
        }
        guard !selectedBackups.isEmpty else {
            presentAlert(title: "バックアップを選んでください", message: "少なくとも1種類のバックアップを保存してください。")
            return
        }
        guard let displayName = displayNameField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !displayName.isEmpty else {
            presentAlert(title: "表示名が空です", message: "ウォレット名を入力してください。")
            return
        }
        setLoading(true)
        Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await service.registerAccount(displayName: displayName, material: material)
                KeychainManager.instance.backupDestinations = Array(self.selectedBackups)
                await MainActor.run {
                    self.setLoading(false)
                    self.presentSuccess(accountId: response.accountId)
                }
            } catch {
                await MainActor.run {
                    self.setLoading(false)
                    self.presentAlert(title: "登録失敗", message: error.localizedDescription)
                }
            }
        }
    }

    private func markBackup(_ destination: KeyBackupDestination) {
        selectedBackups.insert(destination)
        updateBackupStatus()
        updateStartButtonState()
    }

    private func updateBackupStatus() {
        if selectedBackups.isEmpty {
            statusLabel.text = "バックアップ先を選択してください"
        } else {
            let titles = selectedBackups.map { $0.displayName }.sorted()
            statusLabel.text = "選択済み: " + titles.joined(separator: ", ")
        }
    }

    private func updateStartButtonState() {
        let enabled = generatedMaterial != nil && !selectedBackups.isEmpty
        startButton.isEnabled = enabled
        startButton.alpha = enabled ? 1 : 0.6
    }

    private func setLoading(_ loading: Bool) {
        view.isUserInteractionEnabled = !loading
        UIView.animate(withDuration: 0.2) {
            self.activityOverlay.alpha = loading ? 1 : 0
        }
        if loading {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }
    }

    private func presentAlert(title: String, message: String) {
        let alert = PMAlertController(title: title, description: message, image: nil, style: .alert)
        alert.addAction(PMAlertAction(title: "OK", style: .default, action: nil))
        present(alert, animated: true)
    }

    private func presentSuccess(accountId: String) {
        let message = "アカウントID: \(accountId)\n\nSORA Nexus鍵を登録しました。"
        let alert = PMAlertController(title: "準備完了", description: message, image: nil, style: .alert)
        alert.addAction(PMAlertAction(title: "ウォレットへ", style: .default) { [weak self] in
            self?.presentWallet()
        })
        present(alert, animated: true)
    }

    private func presentWallet() {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let contents = storyboard.instantiateViewController(withIdentifier: "Contents") as UIViewController? else {
            return
        }
        contents.modalPresentationStyle = .fullScreen
        present(contents, animated: true)
    }

    private func handleIrohaConnectPayload(_ payload: IrohaConnectPayload) {
        guard let privateKeyData = Data(hexString: payload.privateKeyHex) else {
            presentAlert(title: "無効な秘密鍵", message: "IrohaConnectからの鍵を解析できませんでした")
            return
        }
        do {
            let keypair = try Keypair(privateKeyBytes: privateKeyData)
            let derivedPublicHex = keypair.publicKey.hexEncodedString().lowercased()
            if derivedPublicHex != payload.publicKeyHex.lowercased() {
                presentAlert(title: "公開鍵が一致しません", message: "IrohaConnectからの公開鍵と秘密鍵が一致しません。")
                return
            }
            KeychainManager.instance.accountId = payload.accountId
            KeychainManager.instance.privateKeyHex = payload.privateKeyHex
            KeychainManager.instance.publicKeyHex = payload.publicKeyHex
            KeychainManager.instance.displayName = payload.displayName ?? payload.accountId
            KeychainManager.instance.recoveryMnemonic = nil
            KeychainManager.instance.backupDestinations = []
            let alert = PMAlertController(title: "IrohaConnectと連携", description: "既存のSORA Nexusアカウントを読み込みました。", image: nil, style: .alert)
            alert.addAction(PMAlertAction(title: "ウォレットへ", style: .default) { [weak self] in
                self?.presentWallet()
            })
            present(alert, animated: true)
        } catch {
            presentAlert(title: "鍵の読み込みに失敗", message: error.localizedDescription)
        }
    }
}

extension SoraNexusOnboardingViewController: @MainActor IrohaConnectCoordinatorDelegate {
    func irohaConnectCoordinator(_ coordinator: IrohaConnectCoordinator, didReceive payload: IrohaConnectPayload) {
        handleIrohaConnectPayload(payload)
    }

    func irohaConnectCoordinator(_ coordinator: IrohaConnectCoordinator, didFail error: IrohaConnectError) {
        presentAlert(title: "IrohaConnect", message: error.localizedDescription)
    }
}
