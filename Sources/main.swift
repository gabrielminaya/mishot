import AppKit
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var capture: CaptureController?
    private var shotItem: NSMenuItem!
    private lazy var preferences = PreferencesWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: "MiShot")

        let menu = NSMenu()
        shotItem = menu.addItem(withTitle: "", action: #selector(startCapture), keyEquivalent: "")
        shotItem.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Preferencias…", action: #selector(showPreferences), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Salir de MiShot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        Prefs.shared.onHotKeyChange = { [weak self] in self?.registerHotKey() }
        registerHotKey()

        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
    }

    @objc func startCapture() {
        guard capture == nil else { return }
        let c = CaptureController { [weak self] in self?.capture = nil }
        capture = c
        c.start()
    }

    @objc private func showPreferences() {
        preferences.show()
    }

    private func registerHotKey() {
        let prefs = Prefs.shared
        hotKey = nil
        shotItem.title = "Capturar pantalla  (\(prefs.hotKeyLabel))"
        // While a new shortcut is being recorded, the current one must not fire.
        guard !prefs.isRecordingHotKey else { return }
        hotKey = HotKey(keyCode: prefs.hotKeyCode, modifiers: prefs.hotKeyMods) { [weak self] in
            self?.startCapture()
        }
        prefs.hotKeyConflict = hotKey == nil
    }
}

/// System-wide hotkey via Carbon. Unlike an NSEvent global monitor, it needs no Accessibility permission.
/// Fails (returns nil) if the combination is already taken by another app or the system.
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    fileprivate let action: () -> Void

    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            let me = Unmanaged<HotKey>.fromOpaque(userData!).takeUnretainedValue()
            DispatchQueue.main.async { me.action() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let id = EventHotKeyID(signature: OSType(0x4D53_4854), id: 1) // 'MSHT'
        guard RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr else {
            return nil
        }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
