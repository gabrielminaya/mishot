import AppKit

final class ToolbarView: NSView {
    let stack = NSStackView()

    init(vertical: Bool) {
        super.init(frame: .zero)
        appearance = NSAppearance(named: .aqua)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.97, alpha: 0.97).cgColor
        layer?.cornerRadius = 7
        layer?.borderColor = NSColor(white: 0, alpha: 0.18).cgColor
        layer?.borderWidth = 0.5

        stack.orientation = vertical ? .vertical : .horizontal
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        // Padding lives here rather than in stack.edgeInsets: a vertical stack drops the
        // left/right insets from its fitting size, squeezing the swatches against the edges.
        let pad: CGFloat = 6
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: pad),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -pad),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: pad),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -pad),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func fit() { setFrameSize(fittingSize) }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }

    // Swallow clicks on the bar's background so they don't reach the overlay underneath.
    override func mouseDown(with event: NSEvent) {}
}

final class ToolButton: NSButton {
    var isOn = false { didSet { refresh() } }
    private var isHovered = false { didSet { refresh() } }
    private var hoverArea: NSTrackingArea?

    private func refresh() {
        layer?.backgroundColor = isOn ? NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
            : isHovered ? NSColor(white: 0, alpha: 0.08).cgColor : nil
        contentTintColor = isOn ? .controlAccentColor : NSColor(white: 0.2, alpha: 1)
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func viewDidHide() { isHovered = false }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    // SF Symbols give the button uneven top/bottom alignment insets, which makes the
    // frame taller than 28pt and the hover/selected background off-center.
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }

    // SF Symbols carry uneven padding inside their own frame, so centering the image still
    // leaves the glyph a point or so off. Center the glyph's actual ink, pixel-aligned.
    private var ink = NSRect.zero

    override func draw(_ dirtyRect: NSRect) {
        guard let image else { return }
        let s = image.size
        let inkMidY = isFlipped ? s.height - ink.midY : ink.midY
        let r = backingAlignedRect(NSRect(x: bounds.midX - ink.midX, y: bounds.midY - inkMidY, width: s.width, height: s.height),
                                   options: .alignAllEdgesNearest)
        let tint = contentTintColor ?? .labelColor
        let tinted = NSImage(size: s, flipped: false) { rect in
            image.draw(in: rect)
            tint.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: r, from: .zero, operation: .sourceOver, fraction: isHighlighted ? 0.5 : 1,
                    respectFlipped: true, hints: nil)
    }

    /// Bounding box of the image's non-transparent pixels, in image points (bottom-left origin).
    private static func inkRect(of image: NSImage) -> NSRect {
        let scale = 4
        let w = Int(ceil(image.size.width)) * scale, h = Int(ceil(image.size.height)) * scale
        guard w > 0, h > 0, let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let data = rep.bitmapData else { return NSRect(origin: .zero, size: image.size) }
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        var minX = w, maxX = -1, minY = h, maxY = -1
        for y in 0..<h {
            for x in 0..<w where data[y * rep.bytesPerRow + x * 4 + 3] > 40 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return NSRect(origin: .zero, size: image.size) }
        let k = CGFloat(scale)
        // Bitmap rows run top-down; flip to the image's bottom-left origin.
        return NSRect(x: CGFloat(minX) / k, y: CGFloat(h - 1 - maxY) / k,
                      width: CGFloat(maxX - minX + 1) / k, height: CGFloat(maxY - minY + 1) / k)
    }

    convenience init(symbol: String, tip: String, target: AnyObject, action: Selector) {
        self.init(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
        if let image { ink = Self.inkRect(of: image) }
        isBordered = false
        imagePosition = .imageOnly
        toolTip = tip
        self.target = target
        self.action = action
        wantsLayer = true
        layer?.cornerRadius = 5
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 28).isActive = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true
        isOn = false
    }
}

final class SwatchView: NSView {
    let color: NSColor
    private let onTap: () -> Void
    var isOn = false { didSet { needsDisplay = true } }

    init(color: NSColor, onTap: @escaping () -> Void) {
        self.color = color
        self.onTap = onTap
        super.init(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 24).isActive = true
        heightAnchor.constraint(equalToConstant: 24).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let dot = NSBezierPath(ovalIn: bounds.insetBy(dx: 3.5, dy: 3.5))
        color.setFill()
        dot.fill()
        NSColor(white: 0, alpha: 0.3).setStroke()
        dot.lineWidth = 0.5
        dot.stroke()
        if isOn {
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
            NSColor.controlAccentColor.setStroke()
            ring.lineWidth = 2
            ring.stroke()
        }
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func mouseDown(with event: NSEvent) { onTap() }
}
