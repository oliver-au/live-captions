import AppKit
import SwiftUI

/// Callbacks from the caption bar's controls.
struct CaptionActions {
    var toggleMicrophone: () -> Void
    var toggleMode: () -> Void
    var hide: () -> Void
    var showMenu: () -> Void
    var setLines: (Int) -> Void
    /// Moves the floating bar by the mouse's movement since the drag started.
    var moveWindow: (_ phase: DragPhase) -> Void
}

enum DragPhase {
    case began, changed, ended
}

/// The always-on-top caption bar. It never takes focus from the app you're using.
final class CaptionPanel: NSPanel {
    init(model: CaptionModel, settings: Settings, actions: CaptionActions) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 80),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        // Setting isFloatingPanel resets the level to .floating, so it has to come first.
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        acceptsMouseMovedEvents = true
        // The caption text is a scroll view, which blocks background dragging; floating mode
        // moves the panel with its own drag gesture instead (see CaptionView.moveGesture).
        isMovableByWindowBackground = false

        let view = CaptionView(model: model, settings: settings, actions: actions, ui: CaptionUIState())
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        contentView = hosting
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// View state kept outside the view, because SwiftUI's @State macro needs Xcode's plugins.
@Observable
final class CaptionUIState {
    var isHovering = false
    var scrollPosition = ScrollPosition(edge: .bottom)
    var isAtBottom = true
    var lastScrollInteraction = Date.distantPast
    /// Lines and mouse position when a resize drag started.
    var resizeStart: (lines: Int, mouseY: CGFloat)?
    var isMoving = false
}

struct CaptionView: View {
    /// Captions follow live text again this long after the user stops scrolling back.
    private static let resumeFollowingAfter: TimeInterval = 5

    let model: CaptionModel
    let settings: Settings
    let actions: CaptionActions
    let ui: CaptionUIState

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GeometryReader { geometry in
                captionScroller(height: geometry.size.height)
            }
            .padding(.vertical, settings.verticalPadding)

            if ui.isHovering {
                controls
                    .padding(6)
                    .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .gesture(moveGesture, isEnabled: settings.mode == .floating)
        .overlay(alignment: .bottom) { resizeHandle }
        .background(
            RoundedRectangle(cornerRadius: settings.mode == .floating ? 12 : 0, style: .continuous)
                .fill(Color(white: 0.08).opacity(settings.opacity))
        )
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.15)) { ui.isHovering = inside }
        }
    }

    // MARK: - Captions

    private func captionScroller(height: CGFloat) -> some View {
        ScrollView(.vertical) {
            captionText
                .lineSpacing(settings.lineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: Settings.maxTextWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                // Short text sits at the bottom of the bar, like subtitles.
                .frame(minHeight: height, alignment: .bottom)
        }
        .scrollIndicators(.hidden)
        .scrollPosition(Bindable(ui).scrollPosition)
        .defaultScrollAnchor(.bottom)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 4
        } action: { _, atBottom in
            ui.isAtBottom = atBottom
        }
        .onScrollPhaseChange { _, phase in
            if phase != .idle { ui.lastScrollInteraction = Date() }
        }
        .onChange(of: model.revision) {
            let idle = Date().timeIntervalSince(ui.lastScrollInteraction) > Self.resumeFollowingAfter
            if ui.isAtBottom || idle {
                ui.scrollPosition.scrollTo(edge: .bottom)
            }
        }
        .mask(fadeOutTop)
    }

    /// Older lines fade out as they scroll off the top.
    private var fadeOutTop: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                .frame(height: 10)
            Color.black
        }
    }

    private var captionText: Text {
        let font = Font.system(size: settings.fontSize, weight: .medium)
        if model.isEmpty {
            return Text(model.status ?? (model.isRunning ? "Listening…" : "Captions paused"))
                .font(font)
                .foregroundStyle(Color(white: 0.6))
        }
        var string = AttributedString()
        for run in model.displayRuns() {
            var part = AttributedString(run.text)
            switch run.kind {
            case .final:
                part.foregroundColor = Color(white: 0.96)
            case .volatile:
                part.foregroundColor = Color(white: 0.62)
            case .speakerLabel:
                part.foregroundColor = Color(red: 0.5, green: 0.83, blue: 0.71)
            }
            string += part
        }
        return Text(string)
            .font(font)
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 4) {
            iconButton(settings.includeMicrophone ? "mic.fill" : "mic.slash",
                       help: settings.includeMicrophone ? "Stop captioning your microphone" : "Also caption your microphone",
                       action: actions.toggleMicrophone)
            iconButton(settings.mode == .docked ? "pin.slash" : "pin",
                       help: settings.mode == .docked ? "Undock and float anywhere" : "Dock to the top of the screen",
                       action: actions.toggleMode)
            iconButton("eye.slash", help: "Hide captions (show them again from the menu bar icon)", action: actions.hide)
            iconButton("ellipsis.circle", help: "Settings", action: actions.showMenu)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color(white: 0.18).opacity(0.95)))
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color(white: 0.85))
                .frame(width: 34, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// In floating mode, drag anywhere on the bar to move it.
    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { _ in
                if !ui.isMoving {
                    ui.isMoving = true
                    actions.moveWindow(.began)
                }
                actions.moveWindow(.changed)
            }
            .onEnded { _ in
                ui.isMoving = false
                actions.moveWindow(.ended)
            }
    }

    /// Drag the bar's bottom edge to change its height, snapping to whole lines.
    private var resizeHandle: some View {
        ZStack {
            Color.clear
            Capsule()
                .fill(Color(white: ui.isHovering ? 0.45 : 0.25))
                .frame(width: 36, height: 4)
        }
        .frame(height: 10)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { _ in
                    // Screen coordinates stay stable while the panel itself resizes.
                    let mouseY = NSEvent.mouseLocation.y
                    let start = ui.resizeStart ?? (settings.lines, mouseY)
                    ui.resizeStart = start
                    let delta = Int(((start.mouseY - mouseY) / settings.lineHeight).rounded())
                    let lines = min(max(start.lines + delta, Settings.lineRange.lowerBound), Settings.lineRange.upperBound)
                    if lines != settings.lines { actions.setLines(lines) }
                }
                .onEnded { _ in ui.resizeStart = nil }
        )
        .help("Drag to change the height")
    }
}
