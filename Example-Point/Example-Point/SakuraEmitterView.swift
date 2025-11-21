import UIKit
@preconcurrency import CoreMotion

@MainActor
final class SakuraEmitterView: UIView {
    private let motionManager = CMMotionManager()
    private var emitterLayer: CAEmitterLayer { layer as! CAEmitterLayer } // swiftlint:disable:this force_cast

    override class var layerClass: AnyClass {
        CAEmitterLayer.self
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    deinit {
        motionManager.stopDeviceMotionUpdates()
    }

    private func configure() {
        isUserInteractionEnabled = false
        backgroundColor = .clear
        emitterLayer.emitterShape = .line
        emitterLayer.birthRate = 0
        emitterLayer.renderMode = .additive
        emitterLayer.emitterCells = [makePetalCell()]
        emitterLayer.zPosition = -10
        startMotionUpdates()
        emitterLayer.birthRate = 1
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        emitterLayer.emitterSize = CGSize(width: bounds.width, height: 1)
        emitterLayer.emitterPosition = CGPoint(x: bounds.midX, y: -20)
    }

    private func makePetalCell() -> CAEmitterCell {
        let cell = CAEmitterCell()
        cell.name = "sakura"
        cell.contents = makePetalImage()?.cgImage
        cell.birthRate = 4
        cell.lifetime = 20
        cell.lifetimeRange = 6
        cell.velocity = 35
        cell.velocityRange = 20
        cell.yAcceleration = 12
        cell.xAcceleration = 4
        cell.scale = 0.12
        cell.scaleRange = 0.08
        cell.spin = 0.5
        cell.spinRange = 1.0
        cell.emissionLongitude = .pi
        cell.emissionRange = .pi / 8
        cell.alphaRange = 0.4
        cell.alphaSpeed = -0.02
        return cell
    }

    private func makePetalImage(size: CGSize = CGSize(width: 28, height: 18)) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let bounds = CGRect(origin: .zero, size: size)
            let path = UIBezierPath()
            path.move(to: CGPoint(x: bounds.midX, y: bounds.minY))
            path.addCurve(to: CGPoint(x: bounds.maxX, y: bounds.midY),
                          controlPoint1: CGPoint(x: bounds.midX + bounds.width * 0.2, y: bounds.minY + bounds.height * 0.1),
                          controlPoint2: CGPoint(x: bounds.maxX, y: bounds.midY - bounds.height * 0.2))
            path.addCurve(to: CGPoint(x: bounds.midX, y: bounds.maxY),
                          controlPoint1: CGPoint(x: bounds.maxX, y: bounds.midY + bounds.height * 0.2),
                          controlPoint2: CGPoint(x: bounds.midX + bounds.width * 0.1, y: bounds.maxY - bounds.height * 0.05))
            path.addCurve(to: CGPoint(x: bounds.minX, y: bounds.midY),
                          controlPoint1: CGPoint(x: bounds.midX - bounds.width * 0.1, y: bounds.maxY - bounds.height * 0.05),
                          controlPoint2: CGPoint(x: bounds.minX, y: bounds.midY + bounds.height * 0.15))
            path.addCurve(to: CGPoint(x: bounds.midX, y: bounds.minY),
                          controlPoint1: CGPoint(x: bounds.minX, y: bounds.midY - bounds.height * 0.2),
                          controlPoint2: CGPoint(x: bounds.midX - bounds.width * 0.2, y: bounds.minY + bounds.height * 0.1))
            path.close()

            let gradientColors = [UIColor(red: 1, green: 0.77, blue: 0.88, alpha: 0.9).cgColor,
                                  UIColor(red: 1, green: 0.56, blue: 0.76, alpha: 0.8).cgColor]
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                            colors: gradientColors as CFArray,
                                            locations: [0, 1]) else { return }
            let ctx = context.cgContext
            ctx.saveGState()
            path.addClip()
            ctx.drawLinearGradient(gradient,
                                   start: CGPoint(x: bounds.midX, y: bounds.minY),
                                   end: CGPoint(x: bounds.midX, y: bounds.maxY),
                                   options: [])
            ctx.restoreGState()
        }
    }

    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion, let self else { return }
            let gravity = motion.gravity
            let xAcceleration = CGFloat(gravity.x * 25)
            let yAcceleration = CGFloat(12 + abs(gravity.y) * 20)
            let zSpin = CGFloat(gravity.z * 0.5)
            self.emitterLayer.setValue(xAcceleration, forKeyPath: "emitterCells.sakura.xAcceleration")
            self.emitterLayer.setValue(yAcceleration, forKeyPath: "emitterCells.sakura.yAcceleration")
            self.emitterLayer.setValue(zSpin, forKeyPath: "emitterCells.sakura.spin")
        }
    }
}
