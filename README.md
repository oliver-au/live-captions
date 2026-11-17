# Live Captions for macOS

A Windows 11–style live caption bar for macOS 26+. It captions system audio (and optionally your mic) on-device. It has two display modes:

- **Docked to top** (default): a full-width bar right under the menu bar, on top of other windows. Drag its bottom edge to change the height.
- **Floating on top**: a bar you can move anywhere that stays above all other windows.

The bar shows on the main display (the one with the menu bar). To use another display, pick it under **Display** in the menu, or drag the floating bar onto it. If that display is unplugged, the bar moves to the main display, and it moves back when you plug the display in again.

Captions sit in a centered column (max 1000pt wide), newest at the bottom. Scroll up to read back; it follows live text again when you reach the bottom or stop scrolling for 5 seconds.

## Build and run

Build and install it like a normal app (as `/Applications/Live Captions.app`), then open it:

```bash
./scripts/build-app.sh
```

To change the app icon, edit `scripts/make-icon.swift` and run `./scripts/make-icon.sh`.

The app lives in the menu bar (captions bubble icon). It needs:

- **System Audio Recording Only**: to hear system audio. It never sees your screen.
- **Microphone**: only if you turn on "Include microphone".

Ad-hoc signed builds get a new identity every rebuild, so macOS may ask again. Set `CODESIGN_IDENTITY` to a stable signing certificate to avoid that.

## How it works

| Piece | File | Apple framework |
|---|---|---|
| System audio | `AudioSources.swift` | Core Audio process tap |
| Microphone | `AudioSources.swift` | AVAudioEngine |
| Speech to text | `Transcriber.swift` | Speech (`SpeechAnalyzer` + `SpeechTranscriber`, on-device) |
| Caption bar | `CaptionPanel.swift` | AppKit `NSPanel` + SwiftUI |

There are no third-party dependencies and no network code.
