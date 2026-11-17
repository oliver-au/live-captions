import AppKit
import AVFoundation
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings()
    private let model = CaptionModel()

    private var panel: CaptionPanel!
    /// Hidden only takes the bar off screen; captions keep listening. Always starts visible.
    private var isBarHidden = false
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()

    private var systemTranscriber: Transcriber?
    private var systemSource: SystemAudioSource?
    private var micTranscriber: Transcriber?
    private var micSource: MicrophoneSource?
    /// Mouse position and panel origin when a move drag started.
    private var moveStart: (mouse: NSPoint, origin: NSPoint)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon()
        menu.delegate = self
        statusItem.menu = menu

        let actions = CaptionActions(
            toggleMicrophone: { [weak self] in self?.toggleMicrophone() },
            toggleMode: { [weak self] in
                guard let self else { return }
                self.setMode(self.settings.mode == .docked ? .floating : .docked)
            },
            hide: { [weak self] in self?.setBarHidden(true) },
            showMenu: { [weak self] in self?.showMenuAtMouse() },
            setLines: { [weak self] lines in
                self?.settings.lines = lines
                self?.layoutPanel()
            },
            moveWindow: { [weak self] phase in self?.movePanel(phase) }
        )
        panel = CaptionPanel(model: model, settings: settings, actions: actions)
        // Only the user's own resizes are saved, so falling back to the main display while
        // another is unplugged doesn't lose the bar's spot on that display.
        NotificationCenter.default.addObserver(self, selector: #selector(panelResized),
                                               name: NSWindow.didEndLiveResizeNotification, object: panel)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)

        layoutPanel()
        panel.orderFrontRegardless()
        startCaptions()
    }

    // MARK: - Captioning

    private func startCaptions() {
        guard !model.isRunning else { return }
        model.isRunning = true
        model.status = "Starting…"

        let model = self.model
        let systemTranscriber = Transcriber(
            onResult: { text, isFinal in model.update(source: .system, text: text, isFinal: isFinal) },
            onStatus: { status in model.status = status }
        )
        let systemSource = SystemAudioSource { buffer in systemTranscriber.append(buffer) }
        self.systemTranscriber = systemTranscriber
        self.systemSource = systemSource

        Task { @MainActor in
            do {
                try await systemTranscriber.start()
            } catch {
                NSLog("LiveCaptions: speech model failed: \(error)")
                model.status = "Speech model unavailable: \(error.localizedDescription)"
                return
            }
            do {
                try await systemSource.start()
            } catch {
                NSLog("LiveCaptions: system audio failed: \(error)")
                model.status = "Can't capture system audio: \(error.localizedDescription)"
            }
        }
        if settings.includeMicrophone {
            startMicrophone()
        }
    }

    private func stopCaptions() {
        guard model.isRunning else { return }
        model.isRunning = false
        model.status = nil
        let systemSource = self.systemSource, systemTranscriber = self.systemTranscriber
        self.systemSource = nil
        self.systemTranscriber = nil
        Task {
            await systemSource?.stop()
            await systemTranscriber?.stop()
        }
        stopMicrophone()
    }

    private func startMicrophone() {
        guard micSource == nil else { return }
        let model = self.model
        let transcriber = Transcriber(
            onResult: { text, isFinal in model.update(source: .microphone, text: text, isFinal: isFinal) },
            onStatus: { status in model.status = status }
        )
        let source = MicrophoneSource { buffer in transcriber.append(buffer) }
        micTranscriber = transcriber
        micSource = source

        Task { @MainActor in
            guard await MicrophoneSource.requestPermission() else {
                model.status = "Microphone access is off. Allow it in System Settings → Privacy & Security → Microphone."
                return
            }
            do {
                try await transcriber.start()
                try source.start()
            } catch {
                NSLog("LiveCaptions: microphone failed: \(error)")
                model.status = "Couldn't start the microphone: \(error.localizedDescription)"
            }
        }
    }

    private func stopMicrophone() {
        micSource?.stop()
        micSource = nil
        let transcriber = micTranscriber
        micTranscriber = nil
        model.clearVolatile(for: .microphone)
        Task { await transcriber?.stop() }
    }

    private func toggleMicrophone() {
        settings.includeMicrophone.toggle()
        guard model.isRunning else { return }
        if settings.includeMicrophone { startMicrophone() } else { stopMicrophone() }
    }

    // MARK: - Window layout

    /// The screen with the menu bar.
    private var mainScreen: NSScreen? { NSScreen.screens.first }

    /// The display picked in the menu, or the main display if none was picked or it's unplugged.
    private var barScreen: NSScreen? {
        if let id = settings.display, let screen = NSScreen.screens.first(where: { $0.displayID == id }) {
            return screen
        }
        return mainScreen
    }

    private func layoutPanel() {
        guard let screen = barScreen else { return }
        let height = settings.barHeight
        if settings.mode == .docked {
            let visible = screen.visibleFrame
            panel.setFrame(NSRect(x: screen.frame.minX, y: visible.maxY - height,
                                  width: screen.frame.width, height: height), display: true)
        } else {
            panel.setFrame(floatingFrame(on: screen, height: height), display: true)
        }
        panel.minSize = NSSize(width: 300, height: height)
        panel.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: height)
    }

    /// The floating bar's saved spot on `screen`, slid fully onto it if it doesn't fit there,
    /// e.g. because it was saved on a bigger display. Borderless windows aren't kept on screen by macOS.
    private func floatingFrame(on screen: NSScreen, height: CGFloat) -> NSRect {
        var frame = settings.floatingFrame.map { $0.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY) }
            ?? defaultFloatingFrame(on: screen)
        frame.origin.y = frame.maxY - height
        frame.size.height = height
        if screen.frame.contains(frame) { return frame }
        let visible = screen.visibleFrame
        frame.size.width = min(frame.width, visible.width)
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        return frame
    }

    private func defaultFloatingFrame(on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let width = min(900, visible.width - 80)
        return NSRect(x: visible.midX - width / 2, y: visible.minY + 120, width: width, height: settings.barHeight)
    }

    /// Saves the floating bar's spot relative to its display, so it comes back there when that
    /// display is plugged in again. Dragging the bar onto another display makes that its display.
    private func saveFloatingFrame() {
        guard settings.mode == .floating else { return }
        let frame = panel.frame
        func overlap(_ screen: NSScreen) -> CGFloat {
            let shared = frame.intersection(screen.frame)
            return shared.isNull ? 0 : shared.width * shared.height
        }
        if let screen = NSScreen.screens.max(by: { overlap($0) < overlap($1) }), overlap(screen) > 0,
           screen.displayID != barScreen?.displayID {
            settings.display = screen.displayID == mainScreen?.displayID ? nil : screen.displayID
        }
        guard let screen = barScreen else { return }
        settings.floatingFrame = frame.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
    }

    private func setDisplay(_ id: String?) {
        settings.display = id
        layoutPanel()
    }

    private func setBarHidden(_ hidden: Bool) {
        isBarHidden = hidden
        if hidden {
            panel.orderOut(nil)
        } else {
            layoutPanel()
            panel.orderFrontRegardless()
        }
        updateStatusIcon()
    }

    /// The menu bar icon matches the bar's hide button while the bar is hidden.
    private func updateStatusIcon() {
        let name = isBarHidden ? "eye.slash" : "captions.bubble"
        statusItem.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "Live Captions")
    }

    private func setMode(_ mode: DisplayMode) {
        guard mode != settings.mode else { return }
        settings.mode = mode
        layoutPanel()
    }

    private func movePanel(_ phase: DragPhase) {
        // Screen coordinates, so the math stays stable while the panel moves under the mouse.
        let mouse = NSEvent.mouseLocation
        switch phase {
        case .began:
            moveStart = (mouse, panel.frame.origin)
        case .changed:
            guard let start = moveStart else { return }
            panel.setFrameOrigin(NSPoint(x: start.origin.x + mouse.x - start.mouse.x,
                                         y: start.origin.y + mouse.y - start.mouse.y))
        case .ended:
            moveStart = nil
            saveFloatingFrame()
        }
    }

    @objc private func panelResized() {
        saveFloatingFrame()
    }

    @objc private func screensChanged() {
        layoutPanel()
    }

    // MARK: - Menu

    private func showMenuAtMouse() {
        menuNeedsUpdate(menu)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let state = model.isRunning ? "listening" : "paused"
        let header = NSMenuItem(title: "Live captions · \(state)\(isBarHidden ? " (hidden)" : "")", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(item(isBarHidden ? "Show captions" : "Hide captions") { [weak self] in
            guard let self else { return }
            self.setBarHidden(!self.isBarHidden)
        })
        menu.addItem(item(model.isRunning ? "Pause captions" : "Resume captions") { [weak self] in
            guard let self else { return }
            self.model.isRunning ? self.stopCaptions() : self.startCaptions()
        })

        menu.addItem(.separator())
        menu.addItem(item("Docked to top", checked: settings.mode == .docked) { [weak self] in self?.setMode(.docked) })
        menu.addItem(item("Floating on top", checked: settings.mode == .floating) { [weak self] in self?.setMode(.floating) })
        menu.addItem(submenu("Display", [
            item("Main display", checked: settings.display == nil) { [weak self] in self?.setDisplay(nil) },
            .separator(),
        ] + NSScreen.screens.compactMap { screen in
            screen.displayID.map { id in
                item(screen.localizedName, checked: settings.display == id) { [weak self] in self?.setDisplay(id) }
            }
        }))

        menu.addItem(.separator())
        menu.addItem(item("Include microphone", checked: settings.includeMicrophone) { [weak self] in self?.toggleMicrophone() })

        menu.addItem(submenu("Text size", Settings.fontSizes.map { name, size in
            item(name, checked: settings.fontSize == size) { [weak self] in self?.settings.fontSize = size; self?.layoutPanel() }
        }))
        menu.addItem(submenu("Background opacity", Settings.opacities.map { value in
            item("\(Int(value * 100))%", checked: settings.opacity == value) { [weak self] in self?.settings.opacity = value }
        }))

        menu.addItem(.separator())
        menu.addItem(item("Copy transcript") { [weak self] in
            guard let self else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(self.model.transcript, forType: .string)
        })
        menu.addItem(item("Open System Audio Recording settings…") {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!)
        })
        menu.addItem(.separator())
        menu.addItem(openAtLoginItem())
        menu.addItem(item("Quit Live Captions") { NSApp.terminate(nil) })
    }

    /// "Open at login", using macOS's own login items (System Settings → General → Login Items).
    /// Only offered for the copy in /Applications, so the login item never points at a dev build.
    private func openAtLoginItem() -> NSMenuItem {
        guard Bundle.main.bundleURL.path.hasPrefix("/Applications/") else {
            let item = NSMenuItem(title: "Open at login (install in Applications first)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            return item
        }
        let service = SMAppService.mainApp
        return item("Open at login", checked: service.status == .enabled) {
            do {
                if service.status == .enabled {
                    try service.unregister()
                } else {
                    try service.register()
                }
            } catch {
                NSLog("LiveCaptions: open at login failed: \(error)")
            }
            if service.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        }
    }

    private func item(_ title: String, checked: Bool = false, action: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, action: action)
        item.state = checked ? .on : .off
        return item
    }

    private func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        items.forEach(sub.addItem)
        parent.submenu = sub
        return parent
    }
}

private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, action handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func run() { handler() }
}

private extension NSScreen {
    /// Stays the same across restarts and reconnects, unlike the display number.
    var displayID: String? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
}
