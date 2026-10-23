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
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func fit() { setFrameSize(stack.fittingSize) }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }

    // Swallow clicks on the bar's background so they don't reach the overlay underneath.
    override func mouseDown(with event: NSEvent) {}
}

final class ToolButton: NSButton {
    var isOn = false {
        didSet {
            layer?.backgroundColor = isOn ? NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor : nil
            contentTintColor = isOn ? .controlAccentColor : NSColor(white: 0.2, alpha: 1)
        }
    }

    convenience init(symbol: String, tip: String, target: AnyObject, action: Selector) {
        self.init(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
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

    override func mouseDown(with event: NSEvent) { onTap() }
}
