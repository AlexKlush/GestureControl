import AppKit
import AVFoundation

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let cameraManager = CameraManager()
    private var isTracking = false

    var cursorEnabled = false
    var leftHandEnabled = true

    private var cursorMenuItem: NSMenuItem!
    private var leftHandMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildStatusItem()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.requestCameraPermission()
        }
    }

    private func requestCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if granted {
                        self.requestAccessibilityPermission()
                    } else {
                        self.showCameraAlert()
                    }
                }
            }
        case .authorized:
            requestAccessibilityPermission()
        case .denied, .restricted:
            showCameraAlert()
        @unknown default:
            requestAccessibilityPermission()
        }
    }

    private func requestAccessibilityPermission() {
        if AXIsProcessTrusted() { return }

        let alert = NSAlert()
        alert.messageText = "Нужен Универсальный доступ"
        alert.informativeText = "GestureControl нужен доступ в разделе «Универсальный доступ» для управления курсором и системными жестами.\n\nНажмите «Открыть настройки», добавьте GestureControl в список и включите переключатель. Затем перезапустите приложение."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Открыть настройки")
        alert.addButton(withTitle: "Позже")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
    }

    private func showCameraAlert() {
        let alert = NSAlert()
        alert.messageText = "Нужен доступ к камере"
        alert.informativeText = "GestureControl использует камеру для распознавания жестов рук.\n\nОткройте Системные настройки → Конфиденциальность и безопасность → Камера и разрешите доступ для GestureControl. Затем перезапустите приложение."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Открыть настройки")
        alert.addButton(withTitle: "Позже")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!
            NSWorkspace.shared.open(url)
        }
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let btn = statusItem.button {
            btn.image = NSImage(systemSymbolName: "hand.raised.fill", accessibilityDescription: nil)
            btn.image?.isTemplate = true
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let startItem = NSMenuItem(title: "Start Tracking", action: #selector(startTracking), keyEquivalent: "s")
        startItem.target = self
        menu.addItem(startItem)

        let stopItem = NSMenuItem(title: "Stop Tracking", action: #selector(stopTracking), keyEquivalent: "x")
        stopItem.target = self
        menu.addItem(stopItem)

        menu.addItem(.separator())

        cursorMenuItem = NSMenuItem(
            title: cursorEnabled ? "Cursor: ON" : "Cursor: OFF",
            action: #selector(toggleCursor),
            keyEquivalent: "c"
        )
        cursorMenuItem.target = self
        cursorMenuItem.state = cursorEnabled ? .on : .off
        menu.addItem(cursorMenuItem)

        leftHandMenuItem = NSMenuItem(
            title: leftHandEnabled ? "Left Hand: ON" : "Left Hand: OFF",
            action: #selector(toggleLeftHand),
            keyEquivalent: "l"
        )
        leftHandMenuItem.target = self
        leftHandMenuItem.state = leftHandEnabled ? .on : .off
        menu.addItem(leftHandMenuItem)

        menu.addItem(.separator())

        let calibrateItem = NSMenuItem(title: "Calibrate Gestures...", action: #selector(startCalibration), keyEquivalent: "k")
        calibrateItem.target = self
        menu.addItem(calibrateItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        quitItem.isEnabled = true
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func startTracking() {
        guard !isTracking else { return }
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        guard cameraStatus == .authorized else {
            showCameraAlert()
            return
        }
        isTracking = true
        if let btn = statusItem.button {
            btn.image = NSImage(systemSymbolName: "hand.raised.fingers.spread.fill", accessibilityDescription: nil)
            btn.image?.isTemplate = true
        }
        cameraManager.startSession()
    }

    @objc private func stopTracking() {
        guard isTracking else { return }
        isTracking = false
        if let btn = statusItem.button {
            btn.image = NSImage(systemSymbolName: "hand.raised.fill", accessibilityDescription: nil)
            btn.image?.isTemplate = true
        }
        cameraManager.stopSession()
    }

    @objc private func startCalibration() {
        if !isTracking { startTracking() }
        CalibrationManager.shared.startCalibration()
    }

    @objc private func toggleCursor() {
        cursorEnabled.toggle()
        cursorMenuItem.title = cursorEnabled ? "Cursor: ON" : "Cursor: OFF"
        cursorMenuItem.state = cursorEnabled ? .on : .off
    }

    @objc private func toggleLeftHand() {
        leftHandEnabled.toggle()
        leftHandMenuItem.title = leftHandEnabled ? "Left Hand: ON" : "Left Hand: OFF"
        leftHandMenuItem.state = leftHandEnabled ? .on : .off
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        return true
    }
}
