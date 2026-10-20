import SwiftUI
import AppKit
import FocusCore

/// Marker view used so `FloatingTimerPanel` knows when a mouse-down started on an interactive slider rather than the draggable window body.
final class SliderExclusionMarkerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct SliderDragExclusion: NSViewRepresentable {
    func makeNSView(context: Context) -> SliderExclusionMarkerView {
        SliderExclusionMarkerView()
    }
    func updateNSView(_ nsView: SliderExclusionMarkerView, context: Context) {}
}

/// Hosting view that accepts the first click immediately without requiring the floating panel to become active first.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Shared observable sizing controller for the floating LED timer (persisted in UserDefaults).
@MainActor
final class FloatingTimerSizing: ObservableObject {
    static let shared = FloatingTimerSizing()
    static let scaleKey = "FokusBar.floatingTimerScale"
    static let minScale: CGFloat = 0.55
    static let maxScale: CGFloat = 1.35

    @Published private(set) var scale: CGFloat

    var onScaleChanged: ((CGFloat) -> Void)?

    private init() {
        let saved = CGFloat(UserDefaults.standard.double(forKey: Self.scaleKey))
        if saved >= Self.minScale && saved <= Self.maxScale {
            self.scale = saved
        } else {
            self.scale = 1.0
        }
    }

    func setScale(_ newScale: CGFloat, notifyPanel: Bool = true) {
        let clamped = min(Self.maxScale, max(Self.minScale, (newScale * 100).rounded() / 100))
        guard abs(clamped - scale) > 0.002 else { return }
        scale = clamped
        UserDefaults.standard.set(Double(clamped), forKey: Self.scaleKey)
        if notifyPanel {
            onScaleChanged?(clamped)
        }
    }
}

/// Non-activating floating LED timer panel anchored at the top-right corner of the screen (freely movable and resizable by mouse or trackpad pinch).
final class FloatingTimerPanel: NSPanel {
    static let baseSize = NSSize(width: 284, height: 158)
    static var panelSize: NSSize {
        size(forScale: FloatingTimerSizing.shared.scale)
    }
    static func size(forScale scale: CGFloat) -> NSSize {
        let s = min(FloatingTimerSizing.maxScale, max(FloatingTimerSizing.minScale, scale))
        return NSSize(
            width: (baseSize.width * s).rounded(),
            height: (baseSize.height * s).rounded()
        )
    }

    private static let originXKey = "FokusBar.floatingTimerOriginX"
    private static let originYKey = "FokusBar.floatingTimerOriginY"
    private static let hasCustomKey = "FokusBar.floatingTimerHasCustomOrigin"

    private enum ResizeCorner {
        case bottomLeft
        case bottomRight
        case topLeft
        case topRight
    }

    var hasCustomPosition = false
    private var isInteractingWithSlider = false
    private var isMovingWindow = false
    private var activeResizeCorner: ResizeCorner?
    private var dragStartMouse: NSPoint = .zero
    private var dragStartOrigin: NSPoint = .zero
    private var resizeStartFrame: NSRect = .zero
    private var resizeStartScale: CGFloat = 1.0

    init(store: FocusStore) {
        let initialSize = Self.size(forScale: FloatingTimerSizing.shared.scale)
        super.init(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let hosting = FirstMouseHostingView(rootView: FloatingTimerView(store: store, sizing: FloatingTimerSizing.shared))
        hosting.frame = NSRect(origin: .zero, size: initialSize)
        contentView = hosting
        FloatingTimerSizing.shared.onScaleChanged = { [weak self] newScale in
            guard let self else { return }
            self.applyScaleToFrame(newScale, anchorCorner: .bottomLeft, referenceFrame: self.frame)
        }
        loadSavedPosition()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func magnify(with event: NSEvent) {
        let nextScale = min(
            FloatingTimerSizing.maxScale,
            max(FloatingTimerSizing.minScale, FloatingTimerSizing.shared.scale + event.magnification * 0.65)
        )
        FloatingTimerSizing.shared.setScale(nextScale, notifyPanel: false)
        applyScaleToFrame(nextScale, anchorCorner: .bottomLeft, referenceFrame: frame)
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            isMovingWindow = false
            activeResizeCorner = nil
            isInteractingWithSlider = isPointInSlider(event.locationInWindow)
            if !isInteractingWithSlider {
                dragStartMouse = NSEvent.mouseLocation
                dragStartOrigin = frame.origin
                resizeStartFrame = frame
                resizeStartScale = FloatingTimerSizing.shared.scale
                activeResizeCorner = detectResizeCorner(at: event.locationInWindow)
            }
            super.sendEvent(event)

        case .leftMouseDragged:
            if isInteractingWithSlider {
                super.sendEvent(event)
                return
            }
            let currentMouse = NSEvent.mouseLocation
            let dx = currentMouse.x - dragStartMouse.x
            let dy = currentMouse.y - dragStartMouse.y

            if let corner = activeResizeCorner {
                if !isMovingWindow && hypot(dx, dy) > 2.0 {
                    isMovingWindow = true
                }
                if isMovingWindow {
                    let signedDx: CGFloat = (corner == .bottomLeft || corner == .topLeft) ? -dx : dx
                    let signedDy: CGFloat = (corner == .bottomLeft || corner == .bottomRight) ? -dy : dy
                    let scaleDelta = ((signedDx / Self.baseSize.width) + (signedDy / Self.baseSize.height)) / 2.0
                    let nextScale = min(
                        FloatingTimerSizing.maxScale,
                        max(FloatingTimerSizing.minScale, resizeStartScale + scaleDelta)
                    )
                    FloatingTimerSizing.shared.setScale(nextScale, notifyPanel: false)
                    applyScaleToFrame(nextScale, anchorCorner: corner, referenceFrame: resizeStartFrame)
                    return
                }
            } else {
                if !isMovingWindow && hypot(dx, dy) > 2.5 {
                    isMovingWindow = true
                }
                if isMovingWindow {
                    let nextOrigin = NSPoint(x: dragStartOrigin.x + dx, y: dragStartOrigin.y + dy)
                    setFrameOrigin(nextOrigin)
                    saveCustomOrigin(nextOrigin)
                    return
                }
            }
            super.sendEvent(event)

        case .leftMouseUp:
            if isInteractingWithSlider {
                isInteractingWithSlider = false
                super.sendEvent(event)
                return
            }
            activeResizeCorner = nil
            if isMovingWindow {
                isMovingWindow = false
                saveCustomOrigin(frame.origin)
                if let cancelEvent = NSEvent.mouseEvent(
                    with: .leftMouseUp,
                    location: NSPoint(x: -500, y: -500),
                    modifierFlags: event.modifierFlags,
                    timestamp: event.timestamp,
                    windowNumber: windowNumber,
                    context: nil,
                    eventNumber: event.eventNumber,
                    clickCount: 0,
                    pressure: 0
                ) {
                    super.sendEvent(cancelEvent)
                }
                return
            }
            super.sendEvent(event)

        default:
            super.sendEvent(event)
        }
    }

    private func detectResizeCorner(at point: NSPoint) -> ResizeCorner? {
        let w = frame.width
        let h = frame.height
        let zone: CGFloat = 22
        if point.x <= zone && point.y <= zone {
            return .bottomLeft
        }
        if point.x >= w - zone && point.y <= zone {
            return .bottomRight
        }
        if point.x <= 16 && point.y >= h - 16 {
            return .topLeft
        }
        if point.x >= w - 16 && point.y >= h - 16 {
            return .topRight
        }
        return nil
    }

    private func applyScaleToFrame(_ scale: CGFloat, anchorCorner: ResizeCorner, referenceFrame: NSRect) {
        let newSize = Self.size(forScale: scale)
        let newOrigin: NSPoint
        switch anchorCorner {
        case .bottomLeft:
            // Dragging bottom-left keeps top-right anchored
            newOrigin = NSPoint(x: referenceFrame.maxX - newSize.width, y: referenceFrame.maxY - newSize.height)
        case .bottomRight:
            // Dragging bottom-right keeps top-left anchored
            newOrigin = NSPoint(x: referenceFrame.minX, y: referenceFrame.maxY - newSize.height)
        case .topLeft:
            // Dragging top-left keeps bottom-right anchored
            newOrigin = NSPoint(x: referenceFrame.maxX - newSize.width, y: referenceFrame.minY)
        case .topRight:
            // Dragging top-right keeps bottom-left anchored
            newOrigin = NSPoint(x: referenceFrame.minX, y: referenceFrame.minY)
        }
        let nextFrame = NSRect(origin: newOrigin, size: newSize)
        setFrame(nextFrame, display: true)
        contentView?.frame = NSRect(origin: .zero, size: newSize)
        saveCustomOrigin(newOrigin)
    }

    private func isPointInSlider(_ windowPoint: NSPoint) -> Bool {
        guard let root = contentView else { return false }
        let s = max(0.5, FloatingTimerSizing.shared.scale)
        let center = NSPoint(x: root.bounds.midX, y: root.bounds.midY)
        let unscaledPoint = NSPoint(
            x: center.x + (windowPoint.x - center.x) / s,
            y: center.y + (windowPoint.y - center.y) / s
        )
        func search(_ view: NSView) -> Bool {
            if view is SliderExclusionMarkerView {
                let rectInWindow = view.convert(view.bounds, to: nil).insetBy(dx: -6, dy: -4)
                if rectInWindow.contains(windowPoint) || rectInWindow.contains(unscaledPoint) { return true }
            }
            for subview in view.subviews where search(subview) {
                return true
            }
            return false
        }
        return search(root)
    }

    private func saveCustomOrigin(_ origin: NSPoint) {
        hasCustomPosition = true
        let defaults = UserDefaults.standard
        defaults.set(Double(origin.x), forKey: Self.originXKey)
        defaults.set(Double(origin.y), forKey: Self.originYKey)
        defaults.set(true, forKey: Self.hasCustomKey)
    }

    private func loadSavedPosition() {
        let defaults = UserDefaults.standard
        let currentSize = Self.size(forScale: FloatingTimerSizing.shared.scale)
        guard defaults.bool(forKey: Self.hasCustomKey) else { return }
        let x = CGFloat(defaults.double(forKey: Self.originXKey))
        let y = CGFloat(defaults.double(forKey: Self.originYKey))
        let candidate = NSRect(origin: NSPoint(x: x, y: y), size: currentSize)
        if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(candidate.insetBy(dx: 20, dy: 20)) }) {
            hasCustomPosition = true
            setFrame(candidate, display: false)
        }
    }

    func restoreOrPlace(on screen: NSScreen?) {
        let currentSize = Self.size(forScale: FloatingTimerSizing.shared.scale)
        if frame.size != currentSize {
            setFrame(NSRect(origin: frame.origin, size: currentSize), display: true)
        }
        if hasCustomPosition,
           NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame.insetBy(dx: 20, dy: 20)) }) {
            return
        }
        placeInTopRight(of: screen)
    }

    func placeInTopRight(of screen: NSScreen?) {
        let currentSize = Self.size(forScale: FloatingTimerSizing.shared.scale)
        let area = (screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(
            x: area.maxX - currentSize.width - 8,
            y: area.maxY - currentSize.height - 6
        )
        setFrame(NSRect(origin: origin, size: currentSize), display: true)
    }
}

// MARK: - LED Color Palette

private struct LEDPalette {
    let primary: Color
    let core: Color
    let glow: Color
    let dim: Color
    let badgeText: String
    let countsUp: Bool

    static func resolve(for active: ActiveTimer, remaining: TimeInterval) -> LEDPalette {
        let countsUp = active.mode == .stopwatch
        if !active.isRunning {
            return LEDPalette(
                primary: Color(red: 1.0, green: 0.73, blue: 0.16),
                core: Color(red: 1.0, green: 0.93, blue: 0.70),
                glow: Color(red: 1.0, green: 0.65, blue: 0.10),
                dim: Color(red: 1.0, green: 0.73, blue: 0.16).opacity(0.08),
                badgeText: "PAUSIERT",
                countsUp: countsUp
            )
        }
        if !countsUp && active.mode != .rest && remaining <= 60 && remaining > 0 {
            return LEDPalette(
                primary: Color(red: 1.0, green: 0.34, blue: 0.24),
                core: Color(red: 1.0, green: 0.82, blue: 0.76),
                glow: Color(red: 1.0, green: 0.24, blue: 0.16),
                dim: Color(red: 1.0, green: 0.34, blue: 0.24).opacity(0.09),
                badgeText: modeLabel(active.mode),
                countsUp: false
            )
        }
        switch active.mode {
        case .rest:
            return LEDPalette(
                primary: Color(red: 0.68, green: 0.55, blue: 1.0),
                core: Color(red: 0.91, green: 0.87, blue: 1.0),
                glow: Color(red: 0.56, green: 0.40, blue: 0.98),
                dim: Color(red: 0.68, green: 0.55, blue: 1.0).opacity(0.08),
                badgeText: "PAUSE",
                countsUp: false
            )
        case .stopwatch:
            return LEDPalette(
                primary: Color(red: 0.18, green: 0.88, blue: 0.76),
                core: Color(red: 0.82, green: 1.0, blue: 0.96),
                glow: Color(red: 0.10, green: 0.78, blue: 0.68),
                dim: Color(red: 0.18, green: 0.88, blue: 0.76).opacity(0.08),
                badgeText: "STOPPUHR",
                countsUp: true
            )
        case .focus, .countdown:
            return LEDPalette(
                primary: Color(red: 0.24, green: 0.74, blue: 1.0),
                core: Color(red: 0.84, green: 0.95, blue: 1.0),
                glow: Color(red: 0.16, green: 0.58, blue: 1.0),
                dim: Color(red: 0.24, green: 0.74, blue: 1.0).opacity(0.08),
                badgeText: modeLabel(active.mode),
                countsUp: false
            )
        }
    }

    private static func modeLabel(_ mode: TimerMode) -> String {
        switch mode {
        case .focus: "FOKUS"
        case .countdown: "COUNTDOWN"
        case .stopwatch: "STOPPUHR"
        case .rest: "PAUSE"
        }
    }
}

// MARK: - Main Floating LED Clock View

struct FloatingTimerView: View {
    @ObservedObject var store: FocusStore
    @ObservedObject var sizing: FloatingTimerSizing = .shared
    @State private var hovering = false

    var body: some View {
        let currentSize = FloatingTimerPanel.size(forScale: sizing.scale)
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: store.active == nil)) { context in
            if let active = store.active {
                let referenceDate = active.isRunning ? context.date : store.now
                let elapsed = active.elapsed(at: referenceDate)
                let remaining = active.remaining(at: referenceDate)
                let displaySeconds = active.mode == .stopwatch ? elapsed : ceil(remaining)
                let timeString = TimeFormat.clock(displaySeconds)
                let palette = LEDPalette.resolve(for: active, remaining: remaining)
                let phase = context.date.timeIntervalSinceReferenceDate

                clockBody(
                    active: active,
                    elapsed: elapsed,
                    remaining: remaining,
                    timeString: timeString,
                    palette: palette,
                    phase: phase
                )
                .scaleEffect(sizing.scale, anchor: .center)
            }
        }
        .frame(width: currentSize.width, height: currentSize.height)
    }

    private func clockBody(
        active: ActiveTimer,
        elapsed: TimeInterval,
        remaining: TimeInterval,
        timeString: String,
        palette: LEDPalette,
        phase: TimeInterval
    ) -> some View {
        let pulse = active.isRunning ? (0.5 + 0.5 * sin(phase * .pi * 2.0)) : 0.35
        let housingShape = RoundedRectangle(cornerRadius: 16, style: .continuous)

        return VStack(alignment: .leading, spacing: 6) {
            headerRow(active: active, palette: palette, pulse: pulse)
            ledScreenWell(
                active: active,
                elapsed: elapsed,
                remaining: remaining,
                timeString: timeString,
                palette: palette,
                phase: phase
            )
            audioControlRow(active: active, palette: palette)
            footerRow(active: active, palette: palette)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(width: 260, height: 134)
        .background {
            ZStack {
                housingShape
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.085, green: 0.10, blue: 0.135),
                                Color(red: 0.042, green: 0.05, blue: 0.072)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                housingShape
                    .fill(
                        RadialGradient(
                            colors: [palette.glow.opacity(0.14 + 0.06 * pulse), .clear],
                            center: .center,
                            startRadius: 8,
                            endRadius: 140
                        )
                    )
            }
            .shadow(color: Color.black.opacity(0.55), radius: 10, x: 0, y: 5)
            .shadow(color: palette.glow.opacity(active.isRunning ? 0.26 : 0.12), radius: 8, x: 0, y: 0)
        }
        .overlay {
            ZStack {
                housingShape
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                palette.primary.opacity(0.55 + 0.25 * pulse),
                                Color.white.opacity(0.12),
                                palette.primary.opacity(0.30)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )

                // Subtle bottom-left and bottom-right corner resize grips (visible on hover)
                if hovering {
                    VStack {
                        Spacer()
                        HStack {
                            CornerResizeGrip(isLeft: true, color: palette.primary.opacity(0.65))
                                .help("Ecke ziehen, um die Timer-Größe stufenlos kleiner oder größer zu ziehen")
                            Spacer()
                            CornerResizeGrip(isLeft: false, color: palette.primary.opacity(0.65))
                                .help("Ecke ziehen, um die Timer-Größe stufenlos kleiner oder größer zu ziehen")
                        }
                        .padding(.horizontal, 5)
                        .padding(.bottom, 4)
                    }
                    .allowsHitTesting(false)
                }
            }
        }
        .onHover { hovering = $0 }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("LED-Timeruhr, \(palette.badgeText), \(timeString)")
    }

    // MARK: - Header Row

    private func headerRow(active: ActiveTimer, palette: LEDPalette, pulse: Double) -> some View {
        let sessions = store.state.completedFocusSessions
        let longBreak = TimerChoice.longBreakDue(store)

        return HStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(palette.glow.opacity(0.45 * pulse))
                    .frame(width: 12, height: 12)
                    .blur(radius: 2)
                Circle()
                    .fill(palette.primary)
                    .frame(width: 6.5, height: 6.5)
                    .overlay {
                        Circle()
                            .fill(palette.core)
                            .frame(width: 3, height: 3)
                    }
            }
            .accessibilityHidden(true)

            HStack(spacing: 3.5) {
                Text(palette.badgeText)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(palette.primary)
                Image(systemName: palette.countsUp ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(.system(size: 6.5, weight: .bold))
                    .foregroundStyle(palette.primary.opacity(0.85))
            }

            if active.mode == .focus || active.mode == .rest {
                HStack(spacing: 3) {
                    let filled = active.mode == .rest && longBreak ? 4 : (sessions % 4)
                    ForEach(0..<4, id: \.self) { index in
                        let isCurrent = active.mode == .focus && index == (sessions % 4)
                        Circle()
                            .fill(index < filled ? palette.primary : (isCurrent ? palette.primary.opacity(0.45 + 0.45 * pulse) : Color.white.opacity(0.14)))
                            .frame(width: 4.5, height: 4.5)
                            .shadow(color: (index < filled || isCurrent) ? palette.glow.opacity(0.6) : .clear, radius: 2)
                    }
                }
                .padding(.leading, 1)
                .accessibilityHidden(true)
            }

            Spacer(minLength: 2)

            if store.totalBlockedItemsCount > 0 && (active.mode == .focus || store.preferences.blocksAppsInAllWorkModes) {
                let isBlocking = store.isAppBlockerActive
                Button {
                    store.requestToggleBlockerDuringSession()
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: isBlocking ? "lock.shield.fill" : "lock.shield")
                            .font(.system(size: 7.5, weight: .bold))
                        Text("\(store.totalBlockedItemsCount)")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(isBlocking ? palette.core : Color.white.opacity(0.45))
                    .padding(.horizontal, 4.5)
                    .frame(height: 17)
                    .background(
                        RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                            .fill(isBlocking ? palette.primary.opacity(0.20) : Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                            .strokeBorder(isBlocking ? palette.primary.opacity(0.40) : Color.white.opacity(0.12), lineWidth: 0.7)
                    )
                }
                .buttonStyle(.plain)
                .help(isBlocking ? "App- & Web-Blocker aktiv (\(store.totalBlockedItemsCount) Einträge)" : "Blocker pausiert – klicken zum Aktivieren")
            }

            HStack(spacing: 3.5) {
                if active.mode != .stopwatch {
                    Button {
                        store.adjustActiveTimerMinutes(-5)
                    } label: {
                        Text("-5")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.78))
                            .frame(width: 19, height: 17)
                            .background(
                                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.7)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("5 Minuten verkürzen")

                    Button {
                        store.adjustActiveTimerMinutes(5)
                    } label: {
                        Text("+5")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.78))
                            .frame(width: 19, height: 17)
                            .background(
                                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.7)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("5 Minuten verlängern")
                }

                Button {
                    if active.isRunning { store.requestPauseTimer() } else { store.resumeTimer() }
                } label: {
                    Image(systemName: active.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(palette.core)
                        .frame(width: 20, height: 17)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(palette.primary.opacity(0.22))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(palette.primary.opacity(0.45), lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)
                .help(active.isRunning ? "Timer pausieren" : "Timer fortsetzen")
                .accessibilityLabel(active.isRunning ? "Timer pausieren" : "Timer fortsetzen")

                Button {
                    store.requestStopTimer()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.82))
                        .frame(width: 20, height: 17)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.white.opacity(0.10))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)
                .help(active.mode == .rest ? "Pause beenden" : "Timer stoppen")
                .accessibilityLabel(active.mode == .rest ? "Pause beenden" : "Timer stoppen")
            }
        }
    }

    // MARK: - Recessed 7-Segment LED Display Well

    private func ledScreenWell(
        active: ActiveTimer,
        elapsed: TimeInterval,
        remaining: TimeInterval,
        timeString: String,
        palette: LEDPalette,
        phase: TimeInterval
    ) -> some View {
        let progress = active.target > 0 ? min(1, max(0, elapsed / active.target)) : 0
        let remainingFraction = active.target > 0 ? min(1, max(0, remaining / active.target)) : 0
        let wellShape = RoundedRectangle(cornerRadius: 10, style: .continuous)

        return VStack(spacing: 5) {
            HStack(alignment: .center, spacing: 8) {
                SevenSegmentClockCanvas(
                    text: timeString,
                    palette: palette,
                    isRunning: active.isRunning,
                    phase: phase
                )
                .frame(height: 34)

                Spacer(minLength: 2)

                VStack(alignment: .trailing, spacing: 2) {
                    if active.mode == .stopwatch {
                        Text("AKTIV")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.primary)
                        Text("+\(Int(elapsed) % 60)s")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.core.opacity(0.9))
                            .monospacedDigit()
                    } else {
                        Text("\(Int((progress * 100).rounded()))%")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.core)
                            .shadow(color: palette.glow.opacity(0.6), radius: 3)
                            .monospacedDigit()
                        Text("ZIEL \(TimeFormat.clock(active.target))")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundStyle(palette.primary.opacity(0.75))
                            .lineLimit(1)
                    }
                }
            }

            LEDMatrixBar(
                countsUp: palette.countsUp,
                remainingFraction: remainingFraction,
                elapsed: elapsed,
                isRunning: active.isRunning,
                palette: palette,
                phase: phase
            )
            .frame(height: 5)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            ZStack {
                wellShape
                    .fill(Color(red: 0.016, green: 0.022, blue: 0.035))
                LEDGridBackground()
                    .clipShape(wellShape)
                    .opacity(0.22)
            }
        }
        .overlay {
            wellShape
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.8),
                            palette.primary.opacity(0.22)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        }
    }

    // MARK: - LED Audio & Volume Row

    private func audioControlRow(active: ActiveTimer, palette: LEDPalette) -> some View {
        let sound = store.selectedFocusSound
        let isMuted = sound == .off
        let volume = store.preferences.effectiveFocusSoundVolume
        let displayFraction = isMuted ? 0.0 : min(1.0, max(0.0, volume))
        let pctText = isMuted ? "AUS" : "\(Int((volume * 100).rounded()))%"

        return HStack(spacing: 5) {
            Button {
                store.toggleFocusSoundMute()
            } label: {
                Image(systemName: isMuted ? "speaker.slash.fill" : sound.icon)
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(isMuted ? Color.white.opacity(0.45) : palette.core)
                    .frame(width: 18, height: 16)
                    .background(
                        RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                            .fill(isMuted ? Color.white.opacity(0.07) : palette.primary.opacity(0.20))
                    )
            }
            .buttonStyle(.plain)
            .help(isMuted ? "Fokus-Musik einschalten" : "Fokus-Musik stummschalten")

            Menu {
                FocusSoundMenuItems(store: store)
            } label: {
                Text(isMuted ? "Musik: Aus" : sound.shortTitle)
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .tint(.white)
            .fixedSize()

            if sound.isSpotify && !isMuted {
                Button {
                    store.skipSpotifyTrack()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(palette.core)
                        .frame(width: 16, height: 15)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(palette.primary.opacity(0.18))
                        )
                }
                .buttonStyle(.plain)
                .help("Nächster Track in Spotify")
            }

            Spacer(minLength: 2)

            GeometryReader { geo in
                let width = max(1, geo.size.width)
                let fillWidth = max(0, min(width, width * displayFraction))
                let thumbX = max(4, min(width - 4, fillWidth))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.14))
                        .frame(height: 4.5)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [palette.primary, palette.core],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: fillWidth, height: 4.5)
                        .shadow(color: palette.glow.opacity(0.6), radius: 2)

                    if !isMuted {
                        Circle()
                            .fill(palette.core)
                            .frame(width: 8.5, height: 8.5)
                            .shadow(color: palette.glow.opacity(0.8), radius: 2)
                            .position(x: thumbX, y: geo.size.height / 2)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let raw = Double(value.location.x / width)
                            let clamped = min(1.0, max(0.05, raw))
                            store.setFocusSoundVolume(clamped, unmuteIfOff: true)
                        }
                )
            }
            .frame(width: 50, height: 14)
            .background(SliderDragExclusion())
            .help("Lautstärke ziehen")

            Text(pctText)
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundStyle(isMuted ? Color.white.opacity(0.45) : palette.core)
                .frame(width: 26, alignment: .trailing)
                .monospacedDigit()
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3.5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.7)
        )
    }

    // MARK: - Footer Task Row (Draggable + Dashboard Button)

    private func footerRow(active: ActiveTimer, palette: LEDPalette) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "circle.grid.2x3.fill")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Color.white.opacity(hovering ? 0.55 : 0.25))
                .help("Mit der Maus ziehen, um den Timer zu verschieben")

            Image(systemName: FokusTheme.icon(for: active.mode))
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(palette.primary.opacity(0.85))
            Text(active.mode == .rest ? "Zeit zum Durchatmen" : active.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.86))
                .lineLimit(1)
                .truncationMode(.tail)
            if active.mode != .rest && !active.project.isEmpty {
                Text("· \(active.project)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.primary.opacity(0.85))
                    .lineLimit(1)
            }
            Spacer(minLength: 2)

            Menu {
                Section("Timer-Größe (oder Ecken ziehen)") {
                    ForEach([0.60, 0.75, 0.85, 1.00, 1.15], id: \.self) { preset in
                        Button {
                            sizing.setScale(CGFloat(preset))
                        } label: {
                            let pct = Int((preset * 100).rounded())
                            let label: String = switch pct {
                            case 60: "60 % · Sehr kompakt"
                            case 75: "75 % · Kompakt"
                            case 85: "85 % · Mittel"
                            case 100: "100 % · Standard"
                            default: "\(pct) % · Groß"
                            }
                            if abs(Double(sizing.scale) - preset) < 0.04 {
                                Label(label, systemImage: "checkmark")
                            } else {
                                Text(label)
                            }
                        }
                    }
                }
            } label: {
                Text("\(Int((sizing.scale * 100).rounded()))%")
                    .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(hovering ? 0.78 : 0.38))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.white.opacity(hovering ? 0.08 : 0.0))
                    )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Timer-Größe wählen oder untere Ecken mit der Maus kleiner/größer ziehen")

            Button {
                store.openDashboard()
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(hovering ? 0.85 : 0.40))
                    .frame(width: 18, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("FokusBar Dashboard öffnen")
        }
    }
}

private struct CornerResizeGrip: View {
    let isLeft: Bool
    let color: Color

    var body: some View {
        Canvas { context, size in
            var path = Path()
            if isLeft {
                path.move(to: CGPoint(x: 1, y: size.height - 6))
                path.addLine(to: CGPoint(x: 6, y: size.height - 1))
                path.move(to: CGPoint(x: 1, y: size.height - 3))
                path.addLine(to: CGPoint(x: 3, y: size.height - 1))
            } else {
                path.move(to: CGPoint(x: size.width - 1, y: size.height - 6))
                path.addLine(to: CGPoint(x: size.width - 6, y: size.height - 1))
                path.move(to: CGPoint(x: size.width - 1, y: size.height - 3))
                path.addLine(to: CGPoint(x: size.width - 3, y: size.height - 1))
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        }
        .frame(width: 8, height: 8)
    }
}

// MARK: - Subtle Dot-Matrix Substrate Pattern

private struct LEDGridBackground: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 4
            var path = Path()
            var x: CGFloat = 2
            while x < size.width {
                var y: CGFloat = 2
                while y < size.height {
                    path.addRect(CGRect(x: x, y: y, width: 1, height: 1))
                    y += step
                }
                x += step
            }
            context.fill(path, with: .color(.white.opacity(0.15)))
        }
    }
}

// MARK: - 28-Diode Animated LED Matrix Strip

private struct LEDMatrixBar: View {
    let countsUp: Bool
    let remainingFraction: Double
    let elapsed: TimeInterval
    let isRunning: Bool
    let palette: LEDPalette
    let phase: TimeInterval

    private let diodeCount = 28

    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 2.2
            let totalSpacing = spacing * CGFloat(diodeCount - 1)
            let diodeWidth = max(2, (size.width - totalSpacing) / CGFloat(diodeCount))
            let diodeHeight = size.height

            let scannerPos: Double = {
                guard isRunning else { return -10 }
                if countsUp {
                    return (phase.truncatingRemainder(dividingBy: 1.8) / 1.8) * Double(diodeCount)
                } else {
                    let rev = 1.0 - (phase.truncatingRemainder(dividingBy: 2.0) / 2.0)
                    return rev * Double(diodeCount)
                }
            }()

            let activeDiodes: Int = {
                if countsUp {
                    let minuteProgress = (elapsed.truncatingRemainder(dividingBy: 60)) / 60.0
                    return max(1, Int((minuteProgress * Double(diodeCount)).rounded(.up)))
                } else {
                    return max(remainingFraction > 0 ? 1 : 0, Int((remainingFraction * Double(diodeCount)).rounded(.up)))
                }
            }()

            for i in 0..<diodeCount {
                let x = CGFloat(i) * (diodeWidth + spacing)
                let rect = CGRect(x: x, y: 0, width: diodeWidth, height: diodeHeight)
                let capsule = Path(roundedRect: rect, cornerRadius: 1.5)

                let isLit = i < activeDiodes
                let distToScanner = abs(Double(i) - scannerPos)
                let waveBoost = isRunning ? max(0, 1.0 - distToScanner / 3.5) : 0
                let isLeadingEdge = i == activeDiodes - 1

                if isLit || (countsUp && waveBoost > 0.15) {
                    let edgePulse = (isLeadingEdge && isRunning) ? (0.65 + 0.35 * sin(phase * .pi * 4.0)) : 1.0
                    let intensity = isLit
                        ? min(1.0, (0.72 + 0.28 * waveBoost) * edgePulse)
                        : waveBoost * 0.75

                    context.fill(capsule, with: .color(palette.primary.opacity(intensity)))
                    if intensity > 0.82 {
                        let inner = rect.insetBy(dx: 0.6, dy: 0.8)
                        if inner.width > 0 && inner.height > 0 {
                            context.fill(
                                Path(roundedRect: inner, cornerRadius: 1),
                                with: .color(palette.core.opacity(0.75 * intensity))
                            )
                        }
                    }
                } else {
                    context.fill(capsule, with: .color(Color.white.opacity(0.065)))
                }
            }
        }
    }
}

// MARK: - True 7-Segment LED Digit & Colon Renderer

private struct SevenSegmentClockCanvas: View {
    let text: String
    let palette: LEDPalette
    let isRunning: Bool
    let phase: TimeInterval

    /// Bitmask for segments: 0=A(top), 1=B(top-right), 2=C(bottom-right), 3=D(bottom), 4=E(bottom-left), 5=F(top-left), 6=G(middle)
    private static let digitMasks: [Character: UInt8] = [
        "0": 0b0111111,
        "1": 0b0000110,
        "2": 0b1011011,
        "3": 0b1001111,
        "4": 0b1100110,
        "5": 0b1101101,
        "6": 0b1111101,
        "7": 0b0000111,
        "8": 0b1111111,
        "9": 0b1101111
    ]

    var body: some View {
        let chars = Array(text)
        let isLong = chars.count > 5 // e.g. H:MM:SS
        let digitWidth: CGFloat = isLong ? 17.5 : 21.0
        let digitHeight: CGFloat = isLong ? 29.0 : 32.0
        let colonWidth: CGFloat = isLong ? 6.5 : 8.0
        let spacing: CGFloat = isLong ? 3.2 : 4.2
        let thickness: CGFloat = isLong ? 3.3 : 3.9

        Canvas { context, size in
            var unlitPath = Path()
            var litPath = Path()
            var colonUnlitPath = Path()
            var colonLitPath = Path()

            let yOffset = max(0, (size.height - digitHeight) / 2)
            var cursorX: CGFloat = 2

            for ch in chars {
                if ch == ":" {
                    let dots = Self.colonPaths(
                        x: cursorX,
                        y: yOffset,
                        width: colonWidth,
                        height: digitHeight,
                        dotSize: thickness * 0.95
                    )
                    colonUnlitPath.addPath(dots)
                    colonLitPath.addPath(dots)
                    cursorX += colonWidth + spacing
                } else {
                    let mask = Self.digitMasks[ch] ?? 0
                    for seg in 0..<7 {
                        let segPath = Self.segmentPath(
                            segment: seg,
                            x: cursorX,
                            y: yOffset,
                            width: digitWidth,
                            height: digitHeight,
                            thickness: thickness
                        )
                        unlitPath.addPath(segPath)
                        if (mask & (1 << seg)) != 0 {
                            litPath.addPath(segPath)
                        }
                    }
                    cursorX += digitWidth + spacing
                }
            }

            // 1. Ghost / unlit 88:88 segments
            context.fill(unlitPath, with: .color(palette.dim))
            context.fill(colonUnlitPath, with: .color(palette.dim))

            // 2. Colon pulse intensity
            let colonAlpha: Double = isRunning
                ? (0.28 + 0.72 * (0.5 + 0.5 * cos(phase * .pi * 2.0)))
                : 0.85

            // 3. Soft LED bloom / glow layer
            var glowCtx = context
            glowCtx.addFilter(.blur(radius: 3.8))
            glowCtx.fill(litPath, with: .color(palette.glow.opacity(0.75)))
            glowCtx.fill(colonLitPath, with: .color(palette.glow.opacity(0.70 * colonAlpha)))

            // 4. Crisp main LED diode fill
            context.fill(litPath, with: .color(palette.primary))
            context.fill(colonLitPath, with: .color(palette.primary.opacity(colonAlpha)))

            // 5. Hot inner LED filament highlight
            var coreCtx = context
            coreCtx.addFilter(.blur(radius: 0.4))
            coreCtx.fill(litPath, with: .color(palette.core.opacity(0.55)))
            coreCtx.fill(colonLitPath, with: .color(palette.core.opacity(0.55 * colonAlpha)))
        }
    }

    private static func colonPaths(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, dotSize: CGFloat) -> Path {
        var path = Path()
        let cx = x + width / 2
        let topY = y + height * 0.33
        let botY = y + height * 0.67
        let slantTop: CGFloat = 0.45
        let slantBot: CGFloat = -0.45

        let r1 = CGRect(x: cx - dotSize / 2 + slantTop, y: topY - dotSize / 2, width: dotSize, height: dotSize)
        let r2 = CGRect(x: cx - dotSize / 2 + slantBot, y: botY - dotSize / 2, width: dotSize, height: dotSize)
        path.addRoundedRect(in: r1, cornerSize: CGSize(width: dotSize * 0.35, height: dotSize * 0.35))
        path.addRoundedRect(in: r2, cornerSize: CGSize(width: dotSize * 0.35, height: dotSize * 0.35))
        return path
    }

    private static func segmentPath(
        segment: Int,
        x: CGFloat,
        y: CGFloat,
        width w: CGFloat,
        height h: CGFloat,
        thickness t: CGFloat
    ) -> Path {
        let halfT = t / 2
        let gap: CGFloat = 1.05
        let midY = h / 2

        func pt(_ px: CGFloat, _ py: CGFloat) -> CGPoint {
            let slant = (midY - py) * 0.055
            return CGPoint(x: x + px + slant, y: y + py)
        }

        func horizontal(cy: CGFloat) -> Path {
            let left = halfT + gap
            let right = w - halfT - gap
            var p = Path()
            p.move(to: pt(left, cy))
            p.addLine(to: pt(left + halfT, cy - halfT))
            p.addLine(to: pt(right - halfT, cy - halfT))
            p.addLine(to: pt(right, cy))
            p.addLine(to: pt(right - halfT, cy + halfT))
            p.addLine(to: pt(left + halfT, cy + halfT))
            p.closeSubpath()
            return p
        }

        func vertical(cx: CGFloat, top: CGFloat, bottom: CGFloat) -> Path {
            let topY = top + gap
            let botY = bottom - gap
            var p = Path()
            p.move(to: pt(cx, topY))
            p.addLine(to: pt(cx + halfT, topY + halfT))
            p.addLine(to: pt(cx + halfT, botY - halfT))
            p.addLine(to: pt(cx, botY))
            p.addLine(to: pt(cx - halfT, botY - halfT))
            p.addLine(to: pt(cx - halfT, topY + halfT))
            p.closeSubpath()
            return p
        }

        switch segment {
        case 0: return horizontal(cy: halfT)                     // A: top
        case 1: return vertical(cx: w - halfT, top: halfT, bottom: midY) // B: top-right
        case 2: return vertical(cx: w - halfT, top: midY, bottom: h - halfT) // C: bottom-right
        case 3: return horizontal(cy: h - halfT)                 // D: bottom
        case 4: return vertical(cx: halfT, top: midY, bottom: h - halfT) // E: bottom-left
        case 5: return vertical(cx: halfT, top: halfT, bottom: midY)     // F: top-left
        default: return horizontal(cy: midY)                     // G: middle
        }
    }
}
