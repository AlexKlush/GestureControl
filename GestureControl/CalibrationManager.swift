import AppKit
import Vision
import QuartzCore

struct CalibrationData: Codable {
    var pinchEngageThreshold: Float = 0.05
    var pinchReleaseThreshold: Float = 0.08
    var fistCurlDistance: Double = 0.12
    var middleFingerMinDist: Double = 0.40
    var middleFingerIndexMaxConf: Float = 0.50
    var volumePinchMax: Float = 0.35
}

final class CalibrationManager: NSObject {

    static let shared = CalibrationManager()

    private(set) var data = CalibrationData()
    private let storageKey = "GestureCalibrationData"
    private(set) var isActive = false
    private var completionCallback: (() -> Void)?

    private var window: NSWindow?
    private var contentView: NSView!
    private var labelView: NSTextField!
    private var subLabelView: NSTextField!
    private var stepDots: [NSView] = []
    private var ringLayer: CAShapeLayer!
    private var glowLayer: CAShapeLayer!
    private var particleLayers: [CAShapeLayer] = []
    private var emojiLabel: NSTextField!

    private var currentStep = 0
    private var samplesCollected: [[String: Float]] = []
    private var isSampling = false
    private var sampleTimer: Timer?
    private var particleTimer: Timer?
    private let sampleDuration: TimeInterval = 4
    private var stepStartTime = Date()

    private let steps: [(title: String, subtitle: String, emoji: String, hand: String, gesture: String)] = [
        ("Щипок правой руки", "Сведите большой и указательный пальцы вместе", "⚙️", "right", "pinch_closed"),
        ("Отпустите щипок", "Разведите пальцы в стороны", "⚙️", "right", "pinch_open"),
        ("Кулак правой руки", "Сожмите правую руку в кулак", "⚙️", "right", "fist"),
        ("Средний палец левой", "Покажите средний палец тыльной стороной", "⚙️", "left", "middle"),
        ("Максимальная громкость", "Разведите большой и указательный максимально", "⚙️", "left", "vol_max"),
        ("Минимальная громкость", "Сведите большой и указательный вместе", "⚙️", "left", "vol_min"),
    ]

    override init() { super.init(); load() }

    func load() {
        if let saved = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(CalibrationData.self, from: saved) {
            data = decoded
        }
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    func startCalibration(completion: (() -> Void)? = nil) {
        guard !isActive else { return }
        completionCallback = completion
        currentStep = 0
        samplesCollected = Array(repeating: [:], count: steps.count)
        isActive = true
        DispatchQueue.main.async { self.buildWindow() }
    }

    func feed(observations: [VNHumanHandPoseObservation]) {
        guard isActive, isSampling, currentStep < steps.count else { return }
        let step = steps[currentStep]
        var rightHand: VNHumanHandPoseObservation?
        var leftHand: VNHumanHandPoseObservation?
        for obs in observations {
            switch obs.chirality {
            case .left:  rightHand = obs
            case .right: leftHand = obs
            default: break
            }
        }
        guard let obs = (step.hand == "right" ? rightHand : leftHand) else { return }
        guard let wrist = try? obs.recognizedPoint(.wrist), wrist.confidence > 0.4 else { return }
        let thumbPt  = try? obs.recognizedPoint(.thumbTip)
        let indexPt  = try? obs.recognizedPoint(.indexTip)
        let middlePt = try? obs.recognizedPoint(.middleTip)
        switch step.gesture {
        case "pinch_closed", "pinch_open", "vol_max", "vol_min":
            if let t = thumbPt, let i = indexPt, t.confidence > 0.4, i.confidence > 0.4 {
                let d = hypotf(Float(t.location.x - i.location.x), Float(t.location.y - i.location.y))
                accumulate(key: "pinch_dist", value: d)
            }
        case "fist":
            let tips: [VNHumanHandPoseObservation.JointName] = [.indexTip, .middleTip, .ringTip, .littleTip]
            var total: Float = 0; var count: Float = 0
            for tip in tips {
                if let pt = try? obs.recognizedPoint(tip), pt.confidence > 0.3 {
                    total += Float(hypot(pt.location.x - wrist.location.x, pt.location.y - wrist.location.y))
                    count += 1
                }
            }
            if count > 0 { accumulate(key: "curl_dist", value: total / count) }
        case "middle":
            if let m = middlePt, m.confidence > 0.4 {
                accumulate(key: "middle_dist", value: Float(hypot(m.location.x - wrist.location.x, m.location.y - wrist.location.y)))
            }
            accumulate(key: "index_conf", value: Float((try? obs.recognizedPoint(.indexTip))?.confidence ?? 0))
        default: break
        }
    }

    private func accumulate(key: String, value: Float) {
        guard currentStep < samplesCollected.count else { return }
        if let existing = samplesCollected[currentStep][key] {
            samplesCollected[currentStep][key] = existing * 0.7 + value * 0.3
        } else {
            samplesCollected[currentStep][key] = value
        }
    }

    private func buildWindow() {
        let w: CGFloat = 580
        let h: CGFloat = 320
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window?.titlebarAppearsTransparent = true
        window?.titleVisibility = .hidden
        window?.isMovableByWindowBackground = true
        window?.center()
        window?.isReleasedWhenClosed = false
        window?.delegate = self
        window?.level = .floating
        window?.backgroundColor = .clear

        contentView = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        contentView.wantsLayer = true

        let bg = CALayer()
        bg.frame = contentView.bounds
        bg.cornerRadius = 20
        bg.backgroundColor = NSColor(calibratedRed: 0.06, green: 0.06, blue: 0.10, alpha: 0.97).cgColor
        contentView.layer?.addSublayer(bg)

        let border = CALayer()
        border.frame = contentView.bounds
        border.cornerRadius = 20
        border.borderWidth = 1
        border.borderColor = NSColor(white: 1, alpha: 0.08).cgColor
        contentView.layer?.addSublayer(border)

        buildRingAnimation(in: contentView, size: CGSize(width: w, height: h))
        buildStepDots(in: contentView, width: w)
        buildLabels(in: contentView, width: w)

        window?.contentView = contentView
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.showCurrentStep() }
    }

    private func buildRingAnimation(in view: NSView, size: CGSize) {
        let cx = size.width / 2
        let cy = size.height / 2 + 20
        let radius: CGFloat = 88

        for i in 0..<6 {
            let particle = CAShapeLayer()
            let pSize: CGFloat = CGFloat.random(in: 3...6)
            particle.path = CGPath(ellipseIn: CGRect(x: -pSize/2, y: -pSize/2, width: pSize, height: pSize), transform: nil)
            let hue = CGFloat(i) / 6.0
            particle.fillColor = NSColor(hue: hue, saturation: 0.8, brightness: 1.0, alpha: 0.6).cgColor
            particle.position = CGPoint(x: cx + cos(CGFloat(i) * .pi / 3) * radius,
                                        y: cy + sin(CGFloat(i) * .pi / 3) * radius)
            view.layer?.addSublayer(particle)
            particleLayers.append(particle)

            let orbit = CAKeyframeAnimation(keyPath: "position")
            orbit.duration = Double.random(in: 3.0...5.0)
            orbit.repeatCount = .infinity
            orbit.calculationMode = .paced
            var points: [CGPoint] = []
            for a in stride(from: 0.0, through: 2 * Double.pi, by: Double.pi / 18) {
                let r = radius + CGFloat.random(in: -15...15)
                points.append(CGPoint(x: cx + CGFloat(cos(a + Double(i))) * r,
                                      y: cy + CGFloat(sin(a + Double(i))) * r))
            }
            orbit.values = points.map { NSValue(point: $0) }
            particle.add(orbit, forKey: "orbit")
        }

        glowLayer = CAShapeLayer()
        let outerPath = CGPath(ellipseIn: CGRect(x: cx - radius - 12, y: cy - radius - 12,
                                                   width: (radius + 12) * 2, height: (radius + 12) * 2), transform: nil)
        glowLayer.path = outerPath
        glowLayer.fillColor = NSColor.clear.cgColor
        glowLayer.strokeColor = NSColor(calibratedRed: 0.3, green: 0.6, blue: 1.0, alpha: 0.15).cgColor
        glowLayer.lineWidth = 24
        view.layer?.addSublayer(glowLayer)

        ringLayer = CAShapeLayer()
        let ringPath = CGPath(ellipseIn: CGRect(x: cx - radius, y: cy - radius,
                                                 width: radius * 2, height: radius * 2), transform: nil)
        ringLayer.path = ringPath
        ringLayer.fillColor = NSColor.clear.cgColor
        ringLayer.strokeColor = NSColor(calibratedRed: 0.3, green: 0.6, blue: 1.0, alpha: 1.0).cgColor
        ringLayer.lineWidth = 3
        ringLayer.strokeStart = 0
        ringLayer.strokeEnd = 0
        ringLayer.lineCap = .round
        view.layer?.addSublayer(ringLayer)

        let bgRing = CAShapeLayer()
        bgRing.path = ringPath
        bgRing.fillColor = NSColor.clear.cgColor
        bgRing.strokeColor = NSColor(white: 1, alpha: 0.06).cgColor
        bgRing.lineWidth = 3
        view.layer?.insertSublayer(bgRing, below: ringLayer)

        emojiLabel = NSTextField(frame: CGRect(x: cx - 40, y: cy - 30, width: 80, height: 60))
        emojiLabel.stringValue = ""
        emojiLabel.isEditable = false
        emojiLabel.isBordered = false
        emojiLabel.backgroundColor = .clear
        emojiLabel.alignment = .center
        emojiLabel.font = .systemFont(ofSize: 44)
        view.addSubview(emojiLabel)
    }

    private func buildStepDots(in view: NSView, width: CGFloat) {
        let dotSize: CGFloat = 7
        let spacing: CGFloat = 14
        let total = CGFloat(steps.count) * dotSize + CGFloat(steps.count - 1) * (spacing - dotSize)
        var x = (width - total) / 2
        for _ in 0..<steps.count {
            let dot = NSView(frame: CGRect(x: x, y: 30, width: dotSize, height: dotSize))
            dot.wantsLayer = true
            dot.layer?.cornerRadius = dotSize / 2
            dot.layer?.backgroundColor = NSColor(white: 1, alpha: 0.15).cgColor
            view.addSubview(dot)
            stepDots.append(dot)
            x += spacing
        }
    }

    private func buildLabels(in view: NSView, width: CGFloat) {
        labelView = NSTextField(frame: CGRect(x: 20, y: 88, width: width - 40, height: 30))
        labelView.isEditable = false
        labelView.isBordered = false
        labelView.backgroundColor = .clear
        labelView.textColor = .white
        labelView.font = .boldSystemFont(ofSize: 17)
        labelView.alignment = .center
        view.addSubview(labelView)

        subLabelView = NSTextField(frame: CGRect(x: 20, y: 62, width: width - 40, height: 22))
        subLabelView.isEditable = false
        subLabelView.isBordered = false
        subLabelView.backgroundColor = .clear
        subLabelView.textColor = NSColor(white: 0.55, alpha: 1)
        subLabelView.font = .systemFont(ofSize: 12)
        subLabelView.alignment = .center
        view.addSubview(subLabelView)
    }

    private func showCurrentStep() {
        guard currentStep < steps.count else { finishCalibration(); return }
        let step = steps[currentStep]

        DispatchQueue.main.async {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                ctx.allowsImplicitAnimation = true
                self.labelView.alphaValue = 0
                self.subLabelView.alphaValue = 0
                self.emojiLabel.alphaValue = 0
            } completionHandler: {
                self.labelView.stringValue = step.title
                self.subLabelView.stringValue = step.subtitle
                self.emojiLabel.stringValue = step.emoji
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.4
                    ctx.allowsImplicitAnimation = true
                    self.labelView.alphaValue = 1
                    self.subLabelView.alphaValue = 1
                    self.emojiLabel.alphaValue = 1
                }
            }

            for (i, dot) in self.stepDots.enumerated() {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.3
                    ctx.allowsImplicitAnimation = true
                    if i < self.currentStep {
                        dot.layer?.backgroundColor = NSColor(calibratedRed: 0.3, green: 0.6, blue: 1.0, alpha: 1.0).cgColor
                    } else if i == self.currentStep {
                        dot.layer?.backgroundColor = NSColor.white.cgColor
                    } else {
                        dot.layer?.backgroundColor = NSColor(white: 1, alpha: 0.15).cgColor
                    }
                }
            }

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.ringLayer.strokeEnd = 0
            CATransaction.commit()
        }

        stepStartTime = Date()
        isSampling = true
        sampleTimer?.invalidate()
        sampleTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { [weak self] _ in
            guard let self else { return }
            let elapsed = Date().timeIntervalSince(self.stepStartTime)
            let progress = min(elapsed / self.sampleDuration, 1.0)
            DispatchQueue.main.async {
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.033)
                self.ringLayer.strokeEnd = CGFloat(progress)
                let hue = CGFloat(progress) * 0.4
                self.ringLayer.strokeColor = NSColor(hue: 0.6 - hue, saturation: 0.8, brightness: 1.0, alpha: 1.0).cgColor
                CATransaction.commit()
            }
            if elapsed >= self.sampleDuration {
                self.sampleTimer?.invalidate()
                self.isSampling = false
                self.currentStep += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.showCurrentStep() }
            }
        }
        RunLoop.main.add(sampleTimer!, forMode: .common)
    }

    private func finishCalibration() {
        applyCalibration()
        save()
        isActive = false
        DispatchQueue.main.async {
            self.labelView.stringValue = "Готово!"
            self.subLabelView.stringValue = "Настройки применены и сохранены"
            self.emojiLabel.stringValue = "✅"
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.5)
            self.ringLayer.strokeEnd = 1.0
            self.ringLayer.strokeColor = NSColor(calibratedRed: 0.2, green: 0.9, blue: 0.5, alpha: 1.0).cgColor
            CATransaction.commit()
            for dot in self.stepDots {
                dot.layer?.backgroundColor = NSColor(calibratedRed: 0.2, green: 0.9, blue: 0.5, alpha: 1.0).cgColor
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.window?.close()
            self.completionCallback?()
            self.completionCallback = nil
        }
    }

    private func applyCalibration() {
        let s = samplesCollected
        if let v = s[0]["pinch_dist"] { data.pinchEngageThreshold = v * 1.1 }
        if let v = s[1]["pinch_dist"] { data.pinchReleaseThreshold = v * 0.6 }
        if let v = s[2]["curl_dist"]  { data.fistCurlDistance = Double(v) * 1.1 }
        if let v = s[3]["middle_dist"]{ data.middleFingerMinDist = Double(v) * 0.75 }
        if let v = s[3]["index_conf"] { data.middleFingerIndexMaxConf = v * 1.2 }
        if let v = s[4]["pinch_dist"] { data.volumePinchMax = v * 0.9 }
    }
}

extension CalibrationManager: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        sampleTimer?.invalidate()
        isSampling = false
        isActive = false
        completionCallback?()
        completionCallback = nil
    }
}
