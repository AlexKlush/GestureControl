import Vision
import CoreGraphics
import AppKit

final class GestureProcessor {

    private var smoothedX: Double = 0.5
    private var smoothedY: Double = 0.5
    private let emaAlpha: Double = 0.22
    private let deadZoneRadius: Double = 0.007

    private var pinchActive = false
    private var pinchStartTime: Date? = nil
    private var dragActive = false
    private let dragDelay: TimeInterval = 0.3

    private struct PositionSample {
        let x: Float
        let y: Float
        let time: Date
    }

    private var wristHistory: [PositionSample] = []
    private let swipeWindowDuration: TimeInterval = 0.25
    private let horizontalSwipeThreshold: Float = 0.22
    private var lastSwipeTime = Date.distantPast
    private let swipeCooldown: TimeInterval = 0.9

    private var fistRightSince: Date? = nil
    private let fistActivationDelay: TimeInterval = 0.4
    private var fistRightTriggered = false

    private var smoothedVolume: Float = 0.5
    private let leftHandAlpha: Float = 0.25

    private var middleOnlySince: Date? = nil
    private var middleOnlyTriggered = false

    private var twoFingersSince: Date? = nil
    private var twoFingersTriggered = false

    private var prevScrollY: Float? = nil
    private let scrollSensitivity: Float = 800.0
    private let gestureHoldDelay: TimeInterval = 0.35

    private let screenSize: CGSize = NSScreen.main?.frame.size ?? CGSize(width: 1440, height: 900)

    private var appDelegate: AppDelegate? { NSApp.delegate as? AppDelegate }
    private var cal: CalibrationData { CalibrationManager.shared.data }

    func process(observations: [VNHumanHandPoseObservation]) {
        var rightHand: VNHumanHandPoseObservation?
        var leftHand: VNHumanHandPoseObservation?

        for obs in observations {
            switch obs.chirality {
            case .left:  rightHand = obs
            case .right: leftHand = obs
            default: break
            }
        }

        if let right = rightHand {
            handleRightHand(right)
        } else {
            if dragActive { dragActive = false }
            if pinchActive { pinchActive = false }
            pinchStartTime = nil
            wristHistory.removeAll()
            fistRightSince = nil
            fistRightTriggered = false
        }

        if let left = leftHand, appDelegate?.leftHandEnabled == true {
            handleLeftHand(left)
        } else {
            middleOnlySince = nil
            middleOnlyTriggered = false
            twoFingersSince = nil
            twoFingersTriggered = false
            prevScrollY = nil
        }
    }

    private func handleRightHand(_ obs: VNHumanHandPoseObservation) {
        let cursorOn = appDelegate?.cursorEnabled ?? false

        if cursorOn {
            guard
                let indexTip = try? obs.recognizedPoint(.indexTip),
                indexTip.confidence > 0.5
            else { return }

            let rawX = Double(indexTip.location.x)
            let rawY = Double(indexTip.location.y)
            let dist = hypot(rawX - smoothedX, rawY - smoothedY)
            if dist > deadZoneRadius {
                smoothedX += emaAlpha * (rawX - smoothedX)
                smoothedY += emaAlpha * (rawY - smoothedY)
            }

            let screenX = CGFloat(smoothedX) * screenSize.width
            let screenY = (1.0 - CGFloat(smoothedY)) * screenSize.height
            let cursor = CGPoint(x: screenX, y: screenY)

            if dragActive {
                SystemEventBridge.postMouseDragged(to: cursor)
            } else {
                SystemEventBridge.moveCursor(to: cursor)
            }

            if let thumbTip = try? obs.recognizedPoint(.thumbTip), thumbTip.confidence > 0.5 {
                let pinchDist = hypotf(
                    Float(thumbTip.location.x - indexTip.location.x),
                    Float(thumbTip.location.y - indexTip.location.y)
                )
                let now = Date()
                if pinchDist < cal.pinchEngageThreshold {
                    if !pinchActive {
                        pinchActive = true
                        pinchStartTime = now
                    } else if !dragActive, let start = pinchStartTime,
                              now.timeIntervalSince(start) >= dragDelay {
                        dragActive = true
                        SystemEventBridge.postMouseDown(at: cursor)
                    }
                } else if pinchDist > cal.pinchReleaseThreshold, pinchActive {
                    if dragActive {
                        dragActive = false
                        SystemEventBridge.postMouseUp(at: cursor)
                    } else {
                        SystemEventBridge.postMouseDown(at: cursor)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            SystemEventBridge.postMouseUp(at: cursor)
                        }
                    }
                    pinchActive = false
                    pinchStartTime = nil
                }
            }
        }

        let now = Date()

        if handIsFist(obs) {
            if fistRightSince == nil {
                fistRightSince = now
                fistRightTriggered = false
            } else if !fistRightTriggered && now.timeIntervalSince(fistRightSince!) >= fistActivationDelay {
                fistRightTriggered = true
                SystemEventBridge.triggerMissionControl()
            }
        } else {
            fistRightSince = nil
            fistRightTriggered = false
        }

        guard let wrist = try? obs.recognizedPoint(.wrist), wrist.confidence > 0.5 else {
            wristHistory.removeAll()
            return
        }

        let sample = PositionSample(x: Float(wrist.location.x), y: Float(wrist.location.y), time: now)
        wristHistory.append(sample)
        wristHistory = wristHistory.filter { now.timeIntervalSince($0.time) <= swipeWindowDuration }

        guard wristHistory.count >= 4 else { return }
        guard now.timeIntervalSince(lastSwipeTime) > swipeCooldown else { return }
        guard !handIsFist(obs) else { return }

        let oldest = wristHistory.first!
        let dx = sample.x - oldest.x
        let dy = sample.y - oldest.y
        let adx = abs(dx)
        let ady = abs(dy)

        if dx > horizontalSwipeThreshold && adx > ady * 1.5 {
            lastSwipeTime = now
            wristHistory.removeAll()
            SystemEventBridge.moveToLeftSpace()
        } else if dx < -horizontalSwipeThreshold && adx > ady * 1.5 {
            lastSwipeTime = now
            wristHistory.removeAll()
            SystemEventBridge.moveToRightSpace()
        }
    }

    private func handleLeftHand(_ obs: VNHumanHandPoseObservation) {
        guard let wrist = try? obs.recognizedPoint(.wrist), wrist.confidence > 0.4 else { return }
        let now = Date()

        let middleOnly = isMiddleFingerOnly(obs)

        if middleOnly {
            twoFingersSince = nil
            twoFingersTriggered = false
            prevScrollY = nil
            if middleOnlySince == nil {
                middleOnlySince = now
                middleOnlyTriggered = false
            } else if !middleOnlyTriggered && now.timeIntervalSince(middleOnlySince!) >= gestureHoldDelay {
                middleOnlyTriggered = true
                SystemEventBridge.toggleDoNotDisturb()
            }
            return
        }
        middleOnlySince = nil
        middleOnlyTriggered = false

        if isTwoFingers(obs) {
            prevScrollY = nil
            if twoFingersSince == nil {
                twoFingersSince = now
                twoFingersTriggered = false
            } else if !twoFingersTriggered && now.timeIntervalSince(twoFingersSince!) >= gestureHoldDelay {
                twoFingersTriggered = true
                SystemEventBridge.pressPlayPause()
            }
            return
        }
        twoFingersSince = nil
        twoFingersTriggered = false

        if isIndexFingerOnly(obs) {
            guard let indexTip = try? obs.recognizedPoint(.indexTip), indexTip.confidence > 0.5 else { return }
            let currentY = Float(indexTip.location.y)
            if let prevY = prevScrollY {
                let delta = (currentY - prevY) * scrollSensitivity
                if abs(delta) > 0.5 { SystemEventBridge.scroll(delta: Int32(delta)) }
            }
            prevScrollY = currentY
            return
        }
        prevScrollY = nil

        guard
            let thumbTip = try? obs.recognizedPoint(.thumbTip),
            let indexTip = try? obs.recognizedPoint(.indexTip),
            thumbTip.confidence > 0.5,
            indexTip.confidence > 0.5
        else { return }

        let pinchDist = hypotf(
            Float(thumbTip.location.x - indexTip.location.x),
            Float(thumbTip.location.y - indexTip.location.y)
        )
        let target = (pinchDist / cal.volumePinchMax).clamped(to: 0...1)
        smoothedVolume += leftHandAlpha * (target - smoothedVolume)
        SystemEventBridge.setSystemVolume(smoothedVolume)
    }

    private func handIsFist(_ obs: VNHumanHandPoseObservation) -> Bool {
        guard let wrist = try? obs.recognizedPoint(.wrist), wrist.confidence > 0.4 else { return false }
        let tips: [VNHumanHandPoseObservation.JointName] = [.indexTip, .middleTip, .ringTip, .littleTip]
        var curled = 0
        for tip in tips {
            guard let point = try? obs.recognizedPoint(tip), point.confidence > 0.4 else { continue }
            let dist = hypot(point.location.x - wrist.location.x, point.location.y - wrist.location.y)
            if dist < cal.fistCurlDistance { curled += 1 }
        }
        return curled >= 3
    }

    private func isIndexFingerOnly(_ obs: VNHumanHandPoseObservation) -> Bool {
        guard let wrist = try? obs.recognizedPoint(.wrist), wrist.confidence > 0.4 else { return false }
        guard let index = try? obs.recognizedPoint(.indexTip), index.confidence > 0.4 else { return false }
        let indexDist = hypot(index.location.x - wrist.location.x, index.location.y - wrist.location.y)
        guard indexDist > 0.16 else { return false }
        let curledTips: [VNHumanHandPoseObservation.JointName] = [.middleTip, .ringTip, .littleTip]
        var curled = 0
        for tip in curledTips {
            guard let point = try? obs.recognizedPoint(tip), point.confidence > 0.4 else { continue }
            let dist = hypot(point.location.x - wrist.location.x, point.location.y - wrist.location.y)
            if dist < 0.13 { curled += 1 }
        }
        return curled >= 2
    }

    private func isMiddleFingerOnly(_ obs: VNHumanHandPoseObservation) -> Bool {
        guard let wrist  = try? obs.recognizedPoint(.wrist),     wrist.confidence  > 0.4  else { return false }
        guard let middle = try? obs.recognizedPoint(.middleTip), middle.confidence > 0.45 else { return false }
        let middleDist = hypot(middle.location.x - wrist.location.x, middle.location.y - wrist.location.y)
        guard middleDist > cal.middleFingerMinDist else { return false }
        let indexConf = Float((try? obs.recognizedPoint(.indexTip))?.confidence ?? 0)
        return indexConf < cal.middleFingerIndexMaxConf
    }

    private func isTwoFingers(_ obs: VNHumanHandPoseObservation) -> Bool {
        guard let wrist = try? obs.recognizedPoint(.wrist), wrist.confidence > 0.4 else { return false }
        guard let index = try? obs.recognizedPoint(.indexTip), index.confidence > 0.4 else { return false }
        guard let middle = try? obs.recognizedPoint(.middleTip), middle.confidence > 0.4 else { return false }
        let indexDist  = hypot(index.location.x  - wrist.location.x, index.location.y  - wrist.location.y)
        let middleDist = hypot(middle.location.x - wrist.location.x, middle.location.y - wrist.location.y)
        guard indexDist > 0.15 && middleDist > 0.15 else { return false }
        let curledTips: [VNHumanHandPoseObservation.JointName] = [.ringTip, .littleTip]
        var curled = 0
        for tip in curledTips {
            guard let point = try? obs.recognizedPoint(tip), point.confidence > 0.4 else { continue }
            let dist = hypot(point.location.x - wrist.location.x, point.location.y - wrist.location.y)
            if dist < 0.13 { curled += 1 }
        }
        return curled >= 1
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        max(range.lowerBound, min(range.upperBound, self))
    }
}
