import CoreGraphics
import AudioToolbox
import IOKit
import IOKit.graphics
import Darwin
import AppKit

final class SystemEventBridge {

    private init() {}

    private static let mouseSource = CGEventSource(stateID: .hidSystemState)

    static func moveCursor(to point: CGPoint) {
        let evt = CGEvent(mouseEventSource: mouseSource, mouseType: .mouseMoved,
                          mouseCursorPosition: point, mouseButton: .left)
        evt?.post(tap: .cghidEventTap)
    }

    static func postMouseDown(at point: CGPoint) {
        let evt = CGEvent(mouseEventSource: mouseSource, mouseType: .leftMouseDown,
                          mouseCursorPosition: point, mouseButton: .left)
        evt?.post(tap: .cghidEventTap)
    }

    static func postMouseUp(at point: CGPoint) {
        let evt = CGEvent(mouseEventSource: mouseSource, mouseType: .leftMouseUp,
                          mouseCursorPosition: point, mouseButton: .left)
        evt?.post(tap: .cghidEventTap)
    }

    static func postMouseDragged(to point: CGPoint) {
        let evt = CGEvent(mouseEventSource: mouseSource, mouseType: .leftMouseDragged,
                          mouseCursorPosition: point, mouseButton: .left)
        evt?.post(tap: .cghidEventTap)
    }

    static func scroll(delta: Int32) {
        let evt = CGEvent(scrollWheelEvent2Source: mouseSource, units: .pixel,
                          wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0)
        evt?.post(tap: .cghidEventTap)
    }

    static func moveToLeftSpace() {
        osascript("tell application \"System Events\" to key code 123 using control down")
    }

    static func moveToRightSpace() {
        osascript("tell application \"System Events\" to key code 124 using control down")
    }

    static func triggerMissionControl() {
        osascript("tell application \"System Events\" to key code 126 using control down")
    }

    static func showDesktop() {
        osascript("tell application \"System Events\" to key code 103 using {command down}")
    }

    static func pressPlayPause() {
        osascript("tell application \"System Events\" to key code 100")
    }

    static func toggleDoNotDisturb() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let dn = CGEvent(keyboardEventSource: src, virtualKey: 0x2D, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 0x2D, keyDown: false)
        dn?.flags = [.maskCommand]
        up?.flags = [.maskCommand]
        dn?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }

    private static func osascript(_ script: String) {
        DispatchQueue.global(qos: .userInteractive).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            let pipe = Pipe()
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if process.terminationStatus != 0, let msg = String(data: data, encoding: .utf8) {
                    print("[GC] osascript error: \(msg.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
            } catch {
                print("[GC] osascript launch failed: \(error)")
            }
        }
    }

    static func setSystemVolume(_ level: Float) {
        let clamped = max(0.0, min(1.0, level))
        var defaultDevice = AudioDeviceID(0)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var hwSelector = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                   &hwSelector, 0, nil, &dataSize, &defaultDevice)
        var volumeSelector = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var vol = clamped
        AudioObjectSetPropertyData(defaultDevice, &volumeSelector, 0, nil,
                                   UInt32(MemoryLayout<Float>.size), &vol)
    }

    static func setDisplayBrightness(_ level: Float) {
        let clamped = max(0.0, min(1.0, level))
        let display = CGMainDisplayID()
        if tryDisplayServicesBrightness(display, clamped) { return }
        let service = IOServiceGetMatchingService(0, IOServiceMatching("IODisplayConnect"))
        guard service != IO_OBJECT_NULL else { return }
        IODisplaySetFloatParameter(service, 0, "brightness" as CFString, clamped)
        IOObjectRelease(service)
    }

    private static func tryDisplayServicesBrightness(_ display: CGDirectDisplayID, _ level: Float) -> Bool {
        typealias SetBrightnessFunc = @convention(c) (CGDirectDisplayID, Float) -> Int32
        guard
            let handle = dlopen(
                "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
                RTLD_NOW | RTLD_NOLOAD
            ),
            let sym = dlsym(handle, "DisplayServicesSetBrightness")
        else { return false }
        let fn = unsafeBitCast(sym, to: SetBrightnessFunc.self)
        return fn(display, level) == 0
    }
}
