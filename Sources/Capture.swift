import AppKit
import ScreenCaptureKit

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

final class OverlayWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = true
        hasShadow = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Freezes every display by capturing it, then covers each one with a full-screen
/// overlay where the user picks a region. Lives until the capture is copied, saved or cancelled.
final class CaptureController {
    private var windows: [OverlayWindow] = []
    private var views: [OverlayView] = []
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func start() {
        Task { @MainActor in
            do {
                let shots = try await self.captureScreens()
                self.show(shots)
            } catch {
                self.showPermissionAlert(error)
                self.onFinish()
            }
        }
    }

    @MainActor
    private func captureScreens() async throws -> [(NSScreen, CGImage)] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var shots: [(NSScreen, CGImage)] = []
        for screen in NSScreen.screens {
            guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else { continue }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            let scale = screen.backingScaleFactor
            config.width = Int(CGFloat(display.width) * scale)
            config.height = Int(CGFloat(display.height) * scale)
            config.showsCursor = Prefs.shared.showsCursor
            config.captureResolution = .best
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            shots.append((screen, image))
        }
        if shots.isEmpty { throw NSError(domain: "MiShot", code: 1) }
        return shots
    }

    private func show(_ shots: [(NSScreen, CGImage)]) {
        let mouse = NSEvent.mouseLocation
        var keyWindow: OverlayWindow?
        for (screen, image) in shots {
            let window = OverlayWindow(screen: screen)
            let view = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size), shot: image)
            view.controller = self
            window.contentView = view
            window.orderFrontRegardless()
            windows.append(window)
            views.append(view)
            if screen.frame.contains(mouse) { keyWindow = window }
        }
        NSApp.activate(ignoringOtherApps: true)
        if let w = keyWindow ?? windows.first {
            w.makeKeyAndOrderFront(nil)
            w.makeFirstResponder(w.contentView)
        }
    }

    /// Only one display can hold a selection at a time, so starting one clears the rest.
    func focus(_ view: OverlayView) {
        for other in views where other !== view { other.reset() }
        view.window?.makeKey()
        view.window?.makeFirstResponder(view)
    }

    func setHidden(_ hidden: Bool) {
        for w in windows {
            if hidden { w.orderOut(nil) } else { w.orderFrontRegardless() }
        }
        if !hidden, let v = views.first(where: { $0.selection != nil }) {
            NSApp.activate(ignoringOtherApps: true)
            v.window?.makeKey()
            v.window?.makeFirstResponder(v)
        }
    }

    func finish() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        views.removeAll()
        NSApp.hide(nil)
        onFinish()
    }

    private func showPermissionAlert(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "MiShot necesita permiso de Grabación de pantalla"
        alert.informativeText = "Actívalo en Ajustes del Sistema → Privacidad y seguridad → Grabación de pantalla y audio del sistema, y vuelve a abrir MiShot.\n\n(\(error.localizedDescription))"
        alert.addButton(withTitle: "Abrir Ajustes")
        alert.addButton(withTitle: "Cancelar")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
