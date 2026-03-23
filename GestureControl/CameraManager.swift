import AVFoundation
import Vision

final class CameraManager: NSObject {

    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.gesturecontrol.session", qos: .userInteractive)
    private let processingQueue = DispatchQueue(label: "com.gesturecontrol.vision", qos: .userInteractive)
    private let gestureProcessor = GestureProcessor()

    private let handPoseRequest: VNDetectHumanHandPoseRequest = {
        let r = VNDetectHumanHandPoseRequest()
        r.maximumHandCount = 2
        return r
    }()

    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.captureSession.isRunning {
                self.configureIfNeeded()
                self.captureSession.startRunning()
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
        }
    }

    private func configureIfNeeded() {
        guard captureSession.inputs.isEmpty else { return }
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .vga640x480
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
            let deviceInput = try? AVCaptureDeviceInput(device: device),
            captureSession.canAddInput(deviceInput)
        else {
            captureSession.commitConfiguration()
            return
        }
        captureSession.addInput(deviceInput)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        videoOutput.setSampleBufferDelegate(self, queue: processingQueue)
        guard captureSession.canAddOutput(videoOutput) else {
            captureSession.commitConfiguration()
            return
        }
        captureSession.addOutput(videoOutput)
        captureSession.commitConfiguration()
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .upMirrored)
        try? handler.perform([handPoseRequest])
        guard let results = handPoseRequest.results else { return }

        if CalibrationManager.shared.isActive {
            CalibrationManager.shared.feed(observations: results)
        } else if !results.isEmpty {
            gestureProcessor.process(observations: results)
        }
    }
}
