import UIKit
import TextFieldEffects
import IrohaSwift
import PMAlertController

final class RegisterViewController: UIViewController {

    @IBOutlet private weak var backImg: UIImageView!
    @IBOutlet private weak var nameField: HoshiTextField!
    @IBOutlet private weak var registerButton: UIButton!

    private let service = ToriiService.shared

    override func viewDidLoad() {
        super.viewDidLoad()
        installGlassBackground()
        registerButton.layer.borderColor = UIColor.clear.cgColor
        registerButton.applyGlassButtonStyle()
        nameField.applyGlassInputStyle()
        nameField.enforceHeight(56)
        registerButton.enforceHeight(56)
        backImg.alpha = 0.2
        registerButton.addTarget(self, action: #selector(registerAccount), for: .touchUpInside)
        rotateView(targetView: backImg)
        applySoraFonts()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        registerButton.refreshGlassButtonStyleLayout()
    }

    @objc private func registerAccount() {
        guard let alias = nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !alias.isEmpty else {
            presentAlert(title: "エラー", message: "ユーザー名を入力してください")
            return
        }

        let progress = PMAlertController(title: "登録中", description: "鍵を生成しています", image: nil, style: .alert)
        present(progress, animated: true)

        Task { [weak self] in
            guard let self else { return }
            do {
                let mnemonic = try MnemonicGenerator.shared.generate(wordCount: .twelve)
                let material = try SoraNexusKeyMaterial(mnemonic: mnemonic)
                let response = try await service.registerAccount(displayName: alias, material: material)
                KeychainManager.instance.backupDestinations = []
                await MainActor.run {
                    progress.dismiss(animated: true) {
                        self.showSuccess(accountId: response.accountId)
                    }
                }
            } catch {
                await MainActor.run {
                    progress.dismiss(animated: true) {
                        self.presentAlert(title: "エラー", message: error.localizedDescription)
                    }
                }
            }
        }
    }

    private func showSuccess(accountId: String) {
        let description = """
        アカウントID:
        \(accountId)

        Toriiに登録しました。ウォレットを開始できます。
        """
        let alert = PMAlertController(title: "完了", description: description, image: nil, style: .alert)
        alert.addAction(PMAlertAction(title: "アプリを開始", style: .default) { [weak self] in
            guard let self else { return }
            let storyboard = self.storyboard ?? UIStoryboard(name: "Main", bundle: nil)
            if let contents = storyboard.instantiateViewController(withIdentifier: "Contents") as UIViewController? {
                self.present(contents, animated: true)
            }
        })
        present(alert, animated: true)
    }

    private func presentAlert(title: String, message: String) {
        let alert = PMAlertController(title: title, description: message, image: nil, style: .alert)
        alert.addAction(PMAlertAction(title: "OK", style: .cancel, action: nil))
        present(alert, animated: true)
    }

    private func rotateView(targetView: UIImageView, duration: Double = 10.0) {
        UIImageView.animate(withDuration: duration, delay: 0.0, options: .curveLinear, animations: {
            targetView.transform = targetView.transform.rotated(by: CGFloat.pi)
        }) { [weak self] _ in
            self?.rotateView(targetView: targetView, duration: duration)
        }
    }
}
