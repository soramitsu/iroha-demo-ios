/*
 Copyright Soramitsu Co., Ltd. 2016 All Rights Reserved.
 http://soramitsu.co.jp
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */


import UIKit
import AVFoundation
import PMAlertController

final class QRViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    @IBOutlet private weak var cameraRegion: UIImageView!

    private let captureSession = AVCaptureSession()
    private let metadataOutput = AVCaptureMetadataOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.navigationBar.tintColor = UIColor.label
        configureSession()
        applySoraFonts()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tabBarController?.tabBar.isHidden = true
        if !captureSession.isRunning {
            captureSession.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }

    private func configureSession() {
        guard previewLayer == nil else { return }
        captureSession.beginConfiguration()

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let deviceInput = try? AVCaptureDeviceInput(device: device),
              captureSession.canAddInput(deviceInput) else {
            captureSession.commitConfiguration()
            return
        }
        captureSession.addInput(deviceInput)

        guard captureSession.canAddOutput(metadataOutput) else {
            captureSession.commitConfiguration()
            return
        }
        captureSession.addOutput(metadataOutput)
        metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        metadataOutput.metadataObjectTypes = [.qr]

        captureSession.commitConfiguration()

        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.layer.bounds
        view.layer.insertSublayer(previewLayer, below: cameraRegion.layer)
        self.previewLayer = previewLayer

        captureSession.startRunning()
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let readableObject = metadataObjects.compactMap({ $0 as? AVMetadataMachineReadableCodeObject }).first,
              readableObject.type == .qr,
              let stringValue = readableObject.stringValue else {
            return
        }
        captureSession.stopRunning()
        handlePayload(stringValue)
    }

    private func handlePayload(_ value: String) {
        guard let payload = convertStringToDictionary(text: value),
              let account = payload["account"] as? String else {
            presentError(message: "不正なQRコードです")
            return
        }

        if account.caseInsensitiveCompare(KeychainManager.instance.accountId ?? "") == .orderedSame {
            presentError(message: "自分に送信することはできません")
            return
        }

        let amountValue: String?
        if let amount = payload["amount"] as? Int, amount > 0 {
            amountValue = String(amount)
        } else {
            amountValue = nil
        }

        if let sendVC = navigationController?.viewControllers.dropLast().last as? SendViewController {
            sendVC.prefill(receiver: account, amount: amountValue)
        }
        navigationController?.popViewController(animated: true)
    }

    private func presentError(message: String) {
        let alert = PMAlertController(title: "エラー",
                                      description: message,
                                      image: UIImage(named: "tibihash3.png"),
                                      style: .alert)
        alert.addAction(PMAlertAction(title: "OK", style: .cancel, action: { [weak self] in
            guard let self else { return }
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
        }))
        present(alert, animated: true, completion: nil)
    }

    private func convertStringToDictionary(text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
    }
}
