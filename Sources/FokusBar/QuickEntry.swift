import SwiftUI
import AppKit
import Carbon.HIToolbox
import FocusCore

/// System-wide shortcut via Carbon, which works without accessibility permission.
@MainActor
final class GlobalHotKey {
    static let displayName = "⌃⌥Leertaste"
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) { self.action = action }

    /// Control-Option-Space. Returns false when the combination cannot be registered.
    func register() -> Bool {
        unregister()
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }, 1, &spec, context, &handler)
        guard installed == noErr else { unregister(); return false }
        let id = EventHotKeyID(signature: OSType(0x464B_4252), id: 1) // "FKBR"
        guard RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKey) == noErr else { unregister(); return false }
        return true
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil; handler = nil
    }
}

/// Borderless floating panel that takes typing without activating the app, like Spotlight.
/// Esc discards the draft; clicking elsewhere only hides the panel and keeps it.
final class QuickEntryPanel: NSPanel {
    var onCancel: (() -> Void)?
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 620, height: 134), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true; level = .floating; hidesOnDeactivate = false; isReleasedWhenClosed = false
        isOpaque = false; backgroundColor = .clear; hasShadow = true; isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() ?? orderOut(nil) }
}

@MainActor
final class QuickEntryModel: ObservableObject {
    @Published var text = ""
    @Published var focusToken = 0
    @Published var confirmation: String?
    @Published var failed = false
}

struct QuickEntryView: View {
    @ObservedObject var store: FocusStore
    @ObservedObject var model: QuickEntryModel
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                AppGlyph(size: 22)
                Text("Neue Aufgabe")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if model.failed {
                    Label("Nicht gespeichert, Details im Dashboard", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.orange)
                } else if let confirmation = model.confirmation {
                    Label("„\(confirmation)“ angelegt", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(FokusTheme.accent)
                        .lineLimit(1)
                } else {
                    Text("Eingabetaste legt an, Esc schließt")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                }
            }
            QuickAddField(placeholder: "Was steht an? Zum Beispiel: Angebot schreiben #Website @morgen !", text: $model.text, projects: store.projects, focusToken: model.focusToken) { input in
                let title = QuickAddParser.parse(input, now: Date(), knownProjects: store.projects).title
                model.failed = !store.addQuickTask(input)
                guard !model.failed else { return }
                model.confirmation = title
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    if model.confirmation == title { close() }
                }
            }
        }
        .padding(16)
        .frame(width: 620, height: 134, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(FokusTheme.canvas))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(FokusTheme.stroke))
        .tint(FokusTheme.accent)
        .onExitCommand {
            model.text = ""
            close()
        }
        .preferredColorScheme(store.preferences.appearance == "dark" ? .dark : store.preferences.appearance == "light" ? .light : nil)
    }
}
