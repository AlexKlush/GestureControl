<div align="center">

# ✋ GestureControl

**Control macOS with hand gestures using your built-in camera**

[![macOS](https://img.shields.io/badge/macOS-12.0+-blue?style=flat-square&logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange?style=flat-square&logo=swift)](https://swift.org/)
[![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)

</div>

---

## What is this

GestureControl is a native macOS menu bar application that lets you control your computer using hand gestures detected through the built-in FaceTime camera. No additional hardware required.

The app uses **Apple Vision Framework** to track 21 hand landmarks in real time, and **CoreGraphics / AppleScript** to control the system.

---

## System Requirements

| Parameter | Minimum | Recommended |
|---|---|---|
| macOS | **12.0 Monterey** | 13.0 Ventura or newer |
| Chip | Intel or Apple Silicon | Apple Silicon (M1+) |
| Camera | Built-in FaceTime HD | Built-in FaceTime HD |
| RAM | 4 GB | 8 GB |

> ⚠️ **Note:** macOS 12.0 is the hard minimum. The app relies on `VNHumanHandPoseObservation.chirality` — an API introduced in Monterey.

---

## Installation

### Step 1 — Download

Go to **[Releases](../../releases)** and download the latest `GestureControl.dmg`.

### Step 2 — Install

1. Open the downloaded `.dmg` file
2. Drag `GestureControl.app` into the **Applications** folder
3. Eject the disk image

### Step 3 — First Launch

macOS may show a warning *"Developer cannot be verified"* for apps outside the App Store.

**How to bypass:**
- Open **System Settings → Privacy & Security**
- Scroll down to find GestureControl
- Click **Open Anyway**

### Step 4 — Grant Permissions

The app requires two permissions. Without them, gestures won't work.

#### 1. Camera Access
A dialog will appear on first launch — click **Allow**.

If the dialog doesn't appear:
**System Settings → Privacy & Security → Camera → enable GestureControl**

#### 2. Accessibility Access
Required for cursor control and sending system events.

**System Settings → Privacy & Security → Accessibility**
→ Click **+** → find `GestureControl` in Applications → add it and enable the toggle.

> Restart the app after granting permissions.

---

## Gestures

The app uses both hands independently.

### Right Hand

| Gesture | Action |
|---|---|
| ☝️ Index finger extended | Mouse cursor control |
| 🤌 Quick pinch (release fast) | Mouse click |
| 🤌 Pinch and hold (> 0.3s) | Drag |
| ✊ Closed fist (hold ~0.4s) | Mission Control |
| ➡️ Fast swipe right | Previous desktop space |
| ⬅️ Fast swipe left | Next desktop space |

### Left Hand

| Gesture | Action |
|---|---|
| 🖕 Middle finger only (palm facing away) | Toggle Do Not Disturb |
| ✌️ Index + middle finger (hold ~0.35s) | Play / Pause (F8) |
| ☝️ Index finger only | Page scroll |
| 🤏 Pinch (distance between fingers) | System volume |

**Volume:** fingers close together = quiet, fingers spread apart = loud.

---

## Menu Bar Controls

After launch, a ✋ icon appears in the menu bar.

| Item | Description |
|---|---|
| Start Tracking | Enable gesture recognition |
| Stop Tracking | Disable (camera stops) |
| Cursor: ON/OFF | Toggle cursor control |
| Left Hand: ON/OFF | Toggle all left hand gestures |
| Calibrate Gestures... | Open calibration wizard |
| Quit | Exit the app |

> Cursor control is **disabled by default**. Enable it via the menu when needed.

---

## Calibration

Calibration adapts detection thresholds to your hands and lighting conditions. Recommended once on first setup.

**Menu → Calibrate Gestures...**

An animated window with a progress ring will open. The app will ask you to hold 6 gestures for ~2.5 seconds each:

1. **Right pinch** — bring thumb and index finger together
2. **Open right hand** — natural resting position
3. **Right fist** — close your hand
4. **Left middle finger** — show it with palm facing away from camera
5. **Max volume** — spread fingers as wide as possible
6. **Min volume** — bring fingers together

Results are saved automatically and applied on next launch.

---

## Build from Source

```bash
git clone https://github.com/your-username/GestureControl.git
cd GestureControl
open GestureControl.xcodeproj
```

In Xcode: **Product → Archive → Distribute App → Copy App**

**Minimum macOS version** is set in:
`Project → Target GestureControl → General → Minimum Deployments → macOS 12.0`

---

## Privacy

- Camera video is processed **entirely on-device** and never transmitted
- No data collection of any kind
- Vision Framework runs fully locally

---

## Technologies

- **AVFoundation** — camera capture
- **Vision** — hand pose detection (VNDetectHumanHandPoseRequest)
- **CoreGraphics** — mouse event generation
- **AudioToolbox** — system volume control
- **AppleScript / osascript** — space switching, Mission Control

---

<div align="center">

© 2026 Alexey Klushin. All rights reserved.

Distributed under the MIT License. See [LICENSE](LICENSE) for details.

*Built with ❤️ for those who want to control their Mac with their hands*

</div>
