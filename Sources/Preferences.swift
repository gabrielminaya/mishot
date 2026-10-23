import AppKit
import Carbon
import ServiceManagement
import SwiftUI

/// User settings, persisted to UserDefaults on every change.
final class Prefs: ObservableObject {
    static let shared = Prefs()
    private let d = UserDefaults.standard

    /// Called when the hotkey changes or recording starts/stops, so the global hotkey can be re-registered.
    var onHotKeyChange: (() -> Void)?

    @Published var hotKeyCode: UInt32 { didSet { d.set(hotKeyCode, forKey: "hotKeyCode") } }
    @Published var hotKeyMods: UInt32 { didSet { d.set(hotKeyMods, forKey: "hotKeyMods") } }
    @Published var hotKeyLabel: String { didSet { d.set(hotKeyLabel, forKey: "hotKeyLabel") } }
    @Published var hotKeyConflict = false
    @Published var isRecordingHotKey = false { didSet { onHotKeyChange?() } }

    /// When true, ⌘S writes straight to `saveDir`; otherwise a save panel is shown.
    @Published var saveDirectly: Bool { didSet { d.set(saveDirectly, forKey: "saveDirectly") } }
    @Published var saveDir: URL { didSet { d.set(saveDir, forKey: "saveDir") } }
    @Published var copyOnSave: Bool { didSet { d.set(copyOnSave, forKey: "copyOnSave") } }
    @Published var playSound: Bool { didSet { d.set(playSound, forKey: "playSound") } }
    @Published var showsCursor: Bool { didSet { d.set(showsCursor, forKey: "showsCursor") } }

    /// Backed by the system login items rather than UserDefaults, so it stays accurate
    /// if the user removes MiShot from System Settings → General → Login Items.
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled {
        didSet {
            guard launchAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSAlert(error: error).runModal()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private init() {
        hotKeyCode = d.object(forKey: "hotKeyCode") as? UInt32 ?? UInt32(kVK_ANSI_9)
        hotKeyMods = d.object(forKey: "hotKeyMods") as? UInt32 ?? UInt32(cmdKey | shiftKey)
        hotKeyLabel = d.string(forKey: "hotKeyLabel") ?? "⌘⇧9"
        saveDirectly = d.bool(forKey: "saveDirectly")
        saveDir = d.url(forKey: "saveDir")
            ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        copyOnSave = d.bool(forKey: "copyOnSave")
        playSound = d.object(forKey: "playSound") as? Bool ?? true
        showsCursor = d.bool(forKey: "showsCursor")
    }

    /// Opts into launch at login once, on the very first run; afterwards the user's choice wins.
    func enableLaunchAtLoginOnFirstRun() {
        guard !d.bool(forKey: "didSetUpLaunchAtLogin") else { return }
        d.set(true, forKey: "didSetUpLaunchAtLogin")
        try? SMAppService.mainApp.register()
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setHotKey(code: UInt32, mods: UInt32, label: String) {
        hotKeyCode = code
        hotKeyMods = mods
        hotKeyLabel = label
        onHotKeyChange?()
    }

    func resetHotKey() {
        setHotKey(code: UInt32(kVK_ANSI_9), mods: UInt32(cmdKey | shiftKey), label: "⌘⇧9")
    }

    func playCaptureSound() {
        if playSound { NSSound(named: "Pop")?.play() }
    }

    static func fileName() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'a las' HH.mm.ss"
        return "Captura \(f.string(from: Date())).png"
    }
}

// MARK: - Window

final class PreferencesWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(contentViewController: NSHostingController(rootView: PreferencesView(prefs: .shared)))
        window.title = "Preferencias de MiShot"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        self.init(window: window)
    }

    func show() {
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct PreferencesView: View {
    @ObservedObject var prefs: Prefs

    var body: some View {
        Form {
            Section("General") {
                Toggle("Abrir MiShot al arrancar la Mac", isOn: $prefs.launchAtLogin)
            }

            Section("Atajo de teclado") {
                LabeledContent("Capturar pantalla") {
                    HStack {
                        HotKeyRecorder(prefs: prefs)
                        Button("Restablecer") { prefs.resetHotKey() }
                    }
                }
                if prefs.hotKeyConflict {
                    Text("Ese atajo lo está usando otra app o el sistema. Elige otro.")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }

            Section("Guardar (⌘S)") {
                Picker("Al guardar", selection: $prefs.saveDirectly) {
                    Text("Preguntar dónde guardar").tag(false)
                    Text("Guardar directo en la carpeta").tag(true)
                }
                LabeledContent("Carpeta") {
                    HStack {
                        Text(prefs.saveDir.path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Cambiar…", action: chooseFolder)
                    }
                }
                Toggle("Copiar también al portapapeles al guardar", isOn: $prefs.copyOnSave)
            }

            Section("Captura") {
                Toggle("Sonido al copiar o guardar", isOn: $prefs.playSound)
                Toggle("Incluir el cursor en la captura", isOn: $prefs.showsCursor)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize()
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = prefs.saveDir
        panel.prompt = "Elegir"
        if panel.runModal() == .OK, let url = panel.url { prefs.saveDir = url }
    }
}

struct HotKeyRecorder: View {
    @ObservedObject var prefs: Prefs
    @State private var monitor: Any?

    var body: some View {
        Button(action: { prefs.isRecordingHotKey ? stop() : start() }) {
            Text(prefs.isRecordingHotKey ? "Pulsa el atajo…" : prefs.hotKeyLabel)
                .frame(minWidth: 110)
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        prefs.isRecordingHotKey = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stop()
                return nil
            }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let isFKey = Self.functionKeys[event.keyCode] != nil
            guard !flags.isEmpty || isFKey else {
                NSSound.beep()
                return nil
            }
            prefs.setHotKey(code: UInt32(event.keyCode), mods: Self.carbonMods(flags),
                            label: Self.symbols(flags) + Self.keyName(event))
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if prefs.isRecordingHotKey { prefs.isRecordingHotKey = false }
    }

    private static let functionKeys: [UInt16: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    private static let specialKeys: [UInt16: String] = [
        49: "Espacio", 36: "↩", 48: "⇥", 51: "⌫", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    private static func keyName(_ e: NSEvent) -> String {
        if let f = functionKeys[e.keyCode] ?? specialKeys[e.keyCode] { return f }
        return (e.characters(byApplyingModifiers: []) ?? "?").uppercased()
    }

    private static func symbols(_ f: NSEvent.ModifierFlags) -> String {
        (f.contains(.control) ? "⌃" : "") + (f.contains(.option) ? "⌥" : "")
            + (f.contains(.shift) ? "⇧" : "") + (f.contains(.command) ? "⌘" : "")
    }

    private static func carbonMods(_ f: NSEvent.ModifierFlags) -> UInt32 {
        var m = 0
        if f.contains(.command) { m |= cmdKey }
        if f.contains(.shift) { m |= shiftKey }
        if f.contains(.option) { m |= optionKey }
        if f.contains(.control) { m |= controlKey }
        return UInt32(m)
    }
}
