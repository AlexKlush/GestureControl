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
        requestPermissionsIfNeeded()
    }

    private func requestPermissionsIfNeeded() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                if !granted {
                    self.showPermissionAlert(
                        title: "Нужен доступ к камере",
                        message: "GestureControl использует камеру для распознавания жестов. Откройте Системные настройки и разрешите доступ.",
                        settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
                    )
                }
            }
        }

        if !AXIsProcessTrusted() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self.showPermissionAlert(
                    title: "Нужен Универсальный доступ",
                    message: "Для управления курсором и системными жестами нужен доступ в разделе «Универсальный доступ». Нажмите «Открыть настройки» и добавьте GestureControl.",
                    settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                )
            }
        }
    }

    private func showPermissionAlert(title: String, message: String, settingsURL: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Открыть настройки")
        alert.addButton(withTitle: "Позже")
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: settingsURL) {
                NSWorkspace.shared.open(url)
            }
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
        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func promptAccessibilityIfNeeded() {
        let key = kAXTrustedCheckOptionPrompt.takeRetainedValue() as String
        let options = [key: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        let trusted = AXIsProcessTrusted()
        print("[GC] Accessibility trusted: \(trusted)")
    }

    @objc private func startTracking() {
        guard !isTracking else { return }
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
}
