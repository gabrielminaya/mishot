import AppKit
import UniformTypeIdentifiers

private struct Handle: Equatable {
    let dx: Int, dy: Int

    static let all = [(-1, -1), (0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0)].map(Handle.init)

    func point(in r: NSRect) -> NSPoint {
        NSPoint(x: dx < 0 ? r.minX : dx > 0 ? r.maxX : r.midX,
                y: dy < 0 ? r.minY : dy > 0 ? r.maxY : r.midY)
    }

    func resize(_ r: NSRect, to p: NSPoint) -> NSRect {
        var minX = r.minX, maxX = r.maxX, minY = r.minY, maxY = r.maxY
        if dx < 0 { minX = p.x } else if dx > 0 { maxX = p.x }
        if dy < 0 { minY = p.y } else if dy > 0 { maxY = p.y }
        return NSRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY))
    }

    var cursor: NSCursor {
        if #available(macOS 15, *) {
            let pos: NSCursor.FrameResizePosition = switch (dx, dy) {
            case (-1, -1): .bottomLeft
            case (0, -1): .bottom
            case (1, -1): .bottomRight
            case (1, 0): .right
            case (1, 1): .topRight
            case (0, 1): .top
            case (-1, 1): .topLeft
            default: .left
            }
            return .frameResize(position: pos, directions: .all)
        }
        if dx == 0 { return .resizeUpDown }
        if dy == 0 { return .resizeLeftRight }
        return .crosshair
    }
}

private let palette: [NSColor] = [
    NSColor(srgbRed: 1.00, green: 0.18, blue: 0.18, alpha: 1),
    NSColor(srgbRed: 1.00, green: 0.58, blue: 0.00, alpha: 1),
    NSColor(srgbRed: 1.00, green: 0.86, blue: 0.00, alpha: 1),
    NSColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1),
    NSColor(srgbRed: 0.00, green: 0.48, blue: 1.00, alpha: 1),
    NSColor(srgbRed: 0.69, green: 0.32, blue: 0.87, alpha: 1),
    NSColor(srgbRed: 0.00, green: 0.00, blue: 0.00, alpha: 1),
    NSColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 1),
]

final class OverlayView: NSView, NSTextFieldDelegate {
    weak var controller: CaptureController?

    private let shot: CGImage
    private let shotImage: NSImage
    private(set) var selection: NSRect? { didSet { needsDisplay = true } }
    private var annotations: [Annotation] = [] { didSet { needsDisplay = true } }
    private var current: Annotation?
    private var tool: Tool? { didSet { refreshBars() } }

    private var colorIndex = UserDefaults.standard.object(forKey: "colorIndex") as? Int ?? 0 {
        didSet { UserDefaults.standard.set(colorIndex, forKey: "colorIndex"); refreshBars() }
    }
    private var lineWidth = UserDefaults.standard.object(forKey: "lineWidth") as? CGFloat ?? 3 {
        didSet { UserDefaults.standard.set(lineWidth, forKey: "lineWidth"); refreshBars() }
    }
    private var color: NSColor { palette[min(colorIndex, palette.count - 1)] }

    private enum Drag {
        case none
        case creating(NSPoint)
        case moving(NSPoint, NSRect)
        case resizing(Handle, NSRect)
        case drawing
    }
    private var drag = Drag.none
    private var hotHandle: Handle? { didSet { if hotHandle != oldValue { needsDisplay = true } } }
    private var scrollAccum: CGFloat = 0

    private var textField: NSTextField?
    private var textFontSize: CGFloat = 0

    private let sideBar = ToolbarView(vertical: true)
    private let bottomBar = ToolbarView(vertical: false)
    private var toolButtons: [ToolButton] = []
    private var swatches: [SwatchView] = []
    private let widthLabel = NSTextField(labelWithString: "")

    init(frame: NSRect, shot: CGImage) {
        self.shot = shot
        shotImage = NSImage(cgImage: shot, size: frame.size)
        super.init(frame: frame)
        buildBars()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Toolbars

    private func buildBars() {
        for t in Tool.allCases {
            let b = ToolButton(symbol: t.symbol, tip: t.tip, target: self, action: #selector(toolTapped(_:)))
            b.tag = t.rawValue
            toolButtons.append(b)
            sideBar.stack.addArrangedSubview(b)
        }
        sideBar.stack.addArrangedSubview(separator())
        for (i, c) in palette.enumerated() {
            swatches.append(SwatchView(color: c) { [weak self] in self?.colorIndex = i })
        }
        for pair in stride(from: 0, to: swatches.count, by: 2) {
            let row = NSStackView(views: Array(swatches[pair..<min(pair + 2, swatches.count)]))
            row.spacing = 4
            sideBar.stack.addArrangedSubview(row)
        }
        widthLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        widthLabel.textColor = NSColor(white: 0.35, alpha: 1)
        widthLabel.alignment = .center
        widthLabel.toolTip = "Usa la rueda / scroll para cambiar el grosor"
        sideBar.stack.addArrangedSubview(widthLabel)
        sideBar.stack.addArrangedSubview(separator())
        sideBar.stack.addArrangedSubview(ToolButton(symbol: "arrow.uturn.backward", tip: "Deshacer (⌘Z)", target: self, action: #selector(undo)))

        bottomBar.stack.addArrangedSubview(ToolButton(symbol: "doc.on.doc", tip: "Copiar (⌘C)", target: self, action: #selector(copyAndClose)))
        bottomBar.stack.addArrangedSubview(ToolButton(symbol: "square.and.arrow.down", tip: "Guardar (⌘S)", target: self, action: #selector(save)))
        bottomBar.stack.addArrangedSubview(ToolButton(symbol: "xmark", tip: "Cerrar (Esc)", target: self, action: #selector(cancel)))

        for bar in [sideBar, bottomBar] {
            bar.isHidden = true
            addSubview(bar)
        }
        refreshBars()
    }

    private func separator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        return box
    }

    private func refreshBars() {
        for b in toolButtons { b.isOn = b.tag == tool?.rawValue }
        for (i, s) in swatches.enumerated() { s.isOn = i == colorIndex }
        widthLabel.stringValue = "\(Int(lineWidth)) px"
    }

    private func layoutBars() {
        guard let sel = selection, case .none = drag else {
            sideBar.isHidden = true
            bottomBar.isHidden = true
            return
        }
        let gap: CGFloat = 6
        sideBar.fit()
        bottomBar.fit()

        let s = sideBar.frame.size
        var x = sel.maxX + gap
        if x + s.width > bounds.maxX {
            x = sel.minX - gap - s.width
            if x < 0 { x = sel.maxX - s.width - gap }
        }
        let y = min(max(sel.maxY - s.height, 0), bounds.height - s.height)
        sideBar.setFrameOrigin(NSPoint(x: x, y: y))

        let b = bottomBar.frame.size
        var by = sel.minY - gap - b.height
        if by < 0 {
            by = sel.maxY + gap
            if by + b.height > bounds.maxY { by = sel.minY + gap }
        }
        let bx = min(max(sel.maxX - b.width, 0), bounds.width - b.width)
        bottomBar.setFrameOrigin(NSPoint(x: bx, y: by))

        sideBar.isHidden = false
        bottomBar.isHidden = false
        window?.invalidateCursorRects(for: self)
    }

    @objc private func toolTapped(_ sender: ToolButton) {
        commitText()
        let t = Tool(rawValue: sender.tag)
        tool = tool == t ? nil : t
    }

    // MARK: - State

    func reset() {
        cancelText()
        selection = nil
        annotations.removeAll()
        current = nil
        drag = .none
        layoutBars()
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        shotImage.draw(in: bounds)
        let dim = NSColor(white: 0, alpha: 0.4)

        guard let sel = selection, sel.width > 0, sel.height > 0 else {
            dim.setFill()
            bounds.fill()
            return
        }

        let mask = NSBezierPath(rect: bounds)
        mask.appendRect(sel)
        mask.windingRule = .evenOdd
        dim.setFill()
        mask.fill()

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: sel).addClip()
        annotations.forEach { $0.draw() }
        current?.draw()
        NSGraphicsContext.restoreGraphicsState()

        let border = NSBezierPath(rect: sel.insetBy(dx: -0.5, dy: -0.5))
        border.lineWidth = 1
        NSColor.white.setStroke()
        border.stroke()
        border.setLineDash([4, 4], count: 2, phase: 0)
        NSColor(white: 0, alpha: 0.6).setStroke()
        border.stroke()

        for h in Handle.all {
            let p = h.point(in: sel)
            let hot = h == hotHandle
            let half: CGFloat = hot ? 5 : 3.5
            let r = NSRect(x: p.x - half, y: p.y - half, width: half * 2, height: half * 2)
            (hot ? NSColor.controlAccentColor : NSColor.white).setFill()
            r.fill()
            NSColor(white: 0, alpha: 0.6).setStroke()
            NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)).stroke()
        }

        drawSizeLabel(for: sel)
    }

    private func drawSizeLabel(for sel: NSRect) {
        let scale = CGFloat(shot.width) / bounds.width
        let text = NSAttributedString(string: "\(Int((sel.width * scale).rounded())) × \(Int((sel.height * scale).rounded()))", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ])
        let size = text.size()
        var box = NSRect(x: sel.minX, y: sel.maxY + 4, width: size.width + 10, height: size.height + 4)
        if box.maxY > bounds.maxY { box.origin.y = sel.maxY - box.height - 4; box.origin.x += 4 }
        NSColor(white: 0, alpha: 0.7).setFill()
        NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
        text.draw(at: NSPoint(x: box.minX + 5, y: box.minY + 2))
    }

    // MARK: - Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func cursorUpdate(with event: NSEvent) { updateCursor(event) }
    override func mouseMoved(with event: NSEvent) { updateCursor(event) }

    /// Picks the cursor that tells what a click/drag would do at the mouse position.
    private func updateCursor(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        // Toolbars and the text field set their own cursors.
        let overSubview = [sideBar, bottomBar].contains { !$0.isHidden && $0.frame.contains(p) }
            || textField?.frame.contains(p) == true
        let p2 = point(event)
        if case .resizing(let h, _) = drag {
            hotHandle = h
        } else if case .none = drag, !overSubview, let sel = selection {
            hotHandle = handle(at: p2, in: sel)
        } else {
            hotHandle = nil
        }
        if !overSubview { cursor(at: p2).set() }
    }

    private func cursor(at p: NSPoint) -> NSCursor {
        switch drag {
        case .moving: return .closedHand
        case .resizing(let h, _): return h.cursor
        case .creating, .drawing: return .crosshair
        case .none: break
        }
        guard let sel = selection else { return .crosshair }
        if let h = handle(at: p, in: sel) { return h.cursor }
        if sel.contains(p) {
            switch tool {
            case nil: return .openHand
            case .text: return .iBeam
            default: return .crosshair
            }
        }
        // Outside the selection a click only starts a new one if nothing has been drawn yet.
        return annotations.isEmpty ? .crosshair : .arrow
    }

    private func point(_ event: NSEvent) -> NSPoint {
        let p = convert(event.locationInWindow, from: nil)
        return NSPoint(x: min(max(p.x, 0), bounds.width), y: min(max(p.y, 0), bounds.height))
    }

    private func handle(at p: NSPoint, in sel: NSRect) -> Handle? {
        Handle.all.first { h in
            let hp = h.point(in: sel)
            return abs(hp.x - p.x) <= 6 && abs(hp.y - p.y) <= 6
        }
    }

    override func mouseDown(with event: NSEvent) {
        defer { updateCursor(event) }
        let p = point(event)
        if textField != nil {
            commitText()
            return
        }
        guard let sel = selection else {
            beginSelection(at: p)
            return
        }
        if let h = handle(at: p, in: sel) {
            drag = .resizing(h, sel)
            layoutBars()
        } else if sel.contains(p) {
            if tool == .text {
                beginText(at: p)
            } else if let tool, let a = Annotation(tool: tool, at: p, color: color, width: lineWidth) {
                current = a
                drag = .drawing
            } else {
                drag = .moving(p, sel)
            }
        } else if annotations.isEmpty {
            beginSelection(at: p)
        }
    }

    private func beginSelection(at p: NSPoint) {
        controller?.focus(self)
        drag = .creating(p)
        selection = NSRect(origin: p, size: .zero)
        layoutBars()
    }

    override func mouseDragged(with event: NSEvent) {
        defer { updateCursor(event) }
        let p = point(event)
        switch drag {
        case .creating(let start):
            selection = Annotation.rect(start, p)
        case .moving(let start, let orig):
            var r = orig.offsetBy(dx: p.x - start.x, dy: p.y - start.y)
            r.origin.x = min(max(r.minX, 0), bounds.width - r.width)
            r.origin.y = min(max(r.minY, 0), bounds.height - r.height)
            selection = r
        case .resizing(let h, let orig):
            selection = h.resize(orig, to: p)
        case .drawing:
            current?.extend(to: p, constrained: event.modifierFlags.contains(.shift))
            needsDisplay = true
        case .none:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        switch drag {
        case .creating, .resizing:
            if let s = selection, s.width < 3 || s.height < 3 { selection = nil }
        case .drawing:
            if let c = current { annotations.append(c) }
            current = nil
        default:
            break
        }
        drag = .none
        layoutBars()
        updateCursor(event)
    }

    override func scrollWheel(with event: NSEvent) {
        scrollAccum += event.scrollingDeltaY
        let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 8 : 1
        guard abs(scrollAccum) >= threshold else { return }
        lineWidth = min(max(lineWidth + (scrollAccum > 0 ? 1 : -1), 1), 30)
        scrollAccum = 0
    }

    // MARK: - Text

    private func beginText(at p: NSPoint) {
        textFontSize = Annotation.fontSize(for: lineWidth)
        let font = Annotation.font(size: textFontSize)
        let height = ceil(font.ascender - font.descender + font.leading) + 4
        let field = NSTextField(string: "")
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = font
        field.textColor = color
        field.delegate = self
        field.cell?.isScrollable = true
        field.frame = NSRect(x: p.x, y: p.y - height / 2, width: 40, height: height)
        addSubview(field)
        window?.makeFirstResponder(field)
        (field.currentEditor() as? NSTextView)?.insertionPointColor = color
        textField = field
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let f = textField, let font = f.font else { return }
        let w = (f.stringValue as NSString).size(withAttributes: [.font: font]).width + 20
        f.frame.size.width = max(40, w)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            commitText()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelText()
            return true
        }
        return false
    }

    private func commitText() {
        guard let f = textField else { return }
        let text = f.stringValue
        if !text.trimmingCharacters(in: .whitespaces).isEmpty {
            annotations.append(Annotation(text: text,
                                          origin: NSPoint(x: f.frame.minX + 2, y: f.frame.minY + 2),
                                          fontSize: textFontSize,
                                          color: f.textColor ?? color))
        }
        cancelText()
    }

    private func cancelText() {
        guard let f = textField else { return }
        textField = nil
        f.delegate = nil
        f.removeFromSuperview()
        window?.makeFirstResponder(self)
    }

    // MARK: - Keyboard

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: cancel()                       // Esc
        case 36, 76: copyAndClose()             // Enter
        default: super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard textField == nil,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers {
        case "c": copyAndClose()
        case "s": save()
        case "z": undo()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    // MARK: - Actions

    @objc private func undo() {
        if textField != nil { cancelText(); return }
        if !annotations.isEmpty { annotations.removeLast() }
    }

    @objc private func cancel() {
        if textField != nil { cancelText(); return }
        controller?.finish()
    }

    @objc private func copyAndClose() {
        commitText()
        guard let rep = render() else { return }
        copyToClipboard(rep)
        Prefs.shared.playCaptureSound()
        controller?.finish()
    }

    private func copyToClipboard(_ rep: NSBitmapImageRep) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([.png, .tiff], owner: nil)
        pb.setData(rep.representation(using: .png, properties: [:]), forType: .png)
        pb.setData(rep.tiffRepresentation, forType: .tiff)
    }

    @objc private func save() {
        commitText()
        let prefs = Prefs.shared
        guard let rep = render(), let data = rep.representation(using: .png, properties: [:]) else { return }

        let url: URL
        if prefs.saveDirectly {
            url = prefs.saveDir.appendingPathComponent(Prefs.fileName())
        } else {
            controller?.setHidden(true)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.png]
            panel.nameFieldStringValue = Prefs.fileName()
            panel.directoryURL = prefs.saveDir
            NSApp.activate(ignoringOtherApps: true)
            guard panel.runModal() == .OK, let chosen = panel.url else {
                controller?.setHidden(false)
                return
            }
            url = chosen
        }

        do {
            try data.write(to: url)
            if !prefs.saveDirectly { prefs.saveDir = url.deletingLastPathComponent() }
            if prefs.copyOnSave { copyToClipboard(rep) }
            prefs.playCaptureSound()
            controller?.finish()
        } catch {
            controller?.setHidden(true)
            NSApp.activate(ignoringOtherApps: true)
            NSAlert(error: error).runModal()
            controller?.setHidden(false)
        }
    }

    /// Crops the screenshot to the selection at native (Retina) resolution, keeping the
    /// display's color space, and draws the annotations on top.
    private func render() -> NSBitmapImageRep? {
        guard let sel = selection?.intersection(bounds), sel.width >= 1, sel.height >= 1 else { return nil }
        let scale = CGFloat(shot.width) / bounds.width
        let px = CGRect(x: (sel.minX * scale).rounded(),
                        y: ((bounds.height - sel.maxY) * scale).rounded(),
                        width: (sel.width * scale).rounded(),
                        height: (sel.height * scale).rounded())
        guard let crop = shot.cropping(to: px) else { return nil }
        let space = shot.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: crop.width, height: crop.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))

        if !annotations.isEmpty {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -px.minX / scale, y: -(bounds.height - px.maxY / scale))
            annotations.forEach { $0.draw() }
            NSGraphicsContext.restoreGraphicsState()
        }
        return ctx.makeImage().map(NSBitmapImageRep.init(cgImage:))
    }
}
