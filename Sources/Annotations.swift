import AppKit

enum Tool: Int, CaseIterable {
    case pen, line, arrow, rect, marker, text

    var symbol: String {
        switch self {
        case .pen: "pencil"
        case .line: "line.diagonal"
        case .arrow: "arrow.up.right"
        case .rect: "rectangle"
        case .marker: "highlighter"
        case .text: "textformat"
        }
    }

    var tip: String {
        switch self {
        case .pen: "Lápiz"
        case .line: "Línea"
        case .arrow: "Flecha"
        case .rect: "Rectángulo"
        case .marker: "Marcador"
        case .text: "Texto"
        }
    }
}

enum Mark {
    case pen([NSPoint])
    case marker([NSPoint])
    case line(NSPoint, NSPoint)
    case arrow(NSPoint, NSPoint)
    case rect(NSPoint, NSPoint)
    case text(String, NSPoint, CGFloat)
}

struct Annotation {
    var mark: Mark
    var color: NSColor
    var width: CGFloat

    init?(tool: Tool, at p: NSPoint, color: NSColor, width: CGFloat) {
        switch tool {
        case .pen: mark = .pen([p])
        case .marker: mark = .marker([p])
        case .line: mark = .line(p, p)
        case .arrow: mark = .arrow(p, p)
        case .rect: mark = .rect(p, p)
        case .text: return nil
        }
        self.color = color
        self.width = width
    }

    init(text: String, origin: NSPoint, fontSize: CGFloat, color: NSColor) {
        mark = .text(text, origin, fontSize)
        self.color = color
        width = 0
    }

    /// Updates the shape's end point while dragging. When `constrained` (Shift held),
    /// lines and arrows snap to 45° increments and rectangles become squares.
    mutating func extend(to p: NSPoint, constrained: Bool) {
        switch mark {
        case .pen(var pts): pts.append(p); mark = .pen(pts)
        case .marker(var pts): pts.append(p); mark = .marker(pts)
        case .line(let a, _): mark = .line(a, constrained ? Self.snapAngle(a, p) : p)
        case .arrow(let a, _): mark = .arrow(a, constrained ? Self.snapAngle(a, p) : p)
        case .rect(let a, _): mark = .rect(a, constrained ? Self.snapSquare(a, p) : p)
        case .text: break
        }
    }

    static func fontSize(for width: CGFloat) -> CGFloat { 10 + width * 3 }

    static func font(size: CGFloat) -> NSFont { .systemFont(ofSize: size, weight: .semibold) }

    func draw() {
        switch mark {
        case .pen(let pts):
            color.setStroke()
            stroke(Self.polyline(pts), width: width)
        case .marker(let pts):
            color.withAlphaComponent(0.4).setStroke()
            stroke(Self.polyline(pts), width: width * 4)
        case .line(let a, let b):
            color.setStroke()
            stroke(Self.polyline([a, b]), width: width)
        case .arrow(let a, let b):
            drawArrow(from: a, to: b)
        case .rect(let a, let b):
            color.setStroke()
            let path = NSBezierPath(rect: Self.rect(a, b))
            path.lineJoinStyle = .miter
            path.lineWidth = width
            path.stroke()
        case .text(let s, let origin, let size):
            NSAttributedString(string: s, attributes: [
                .font: Self.font(size: size),
                .foregroundColor: color,
            ]).draw(at: origin)
        }
    }

    private func stroke(_ path: NSBezierPath, width: CGFloat) {
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    private func drawArrow(from a: NSPoint, to b: NSPoint) {
        let len = hypot(b.x - a.x, b.y - a.y)
        guard len > 1 else { return }
        let angle = atan2(b.y - a.y, b.x - a.x)
        let head = min(max(12, width * 4), len)
        let spread: CGFloat = .pi / 7
        let p1 = NSPoint(x: b.x - head * cos(angle - spread), y: b.y - head * sin(angle - spread))
        let p2 = NSPoint(x: b.x - head * cos(angle + spread), y: b.y - head * sin(angle + spread))
        let base = NSPoint(x: b.x - head * 0.8 * cos(angle), y: b.y - head * 0.8 * sin(angle))

        color.setStroke()
        stroke(Self.polyline([a, base]), width: width)
        color.setFill()
        let tip = NSBezierPath()
        tip.move(to: b)
        tip.line(to: p1)
        tip.line(to: p2)
        tip.close()
        tip.fill()
    }

    static func polyline(_ pts: [NSPoint]) -> NSBezierPath {
        let path = NSBezierPath()
        guard let first = pts.first else { return path }
        path.move(to: first)
        if pts.count == 1 { path.line(to: first) }
        for p in pts.dropFirst() { path.line(to: p) }
        return path
    }

    static func rect(_ a: NSPoint, _ b: NSPoint) -> NSRect {
        NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    private static func snapAngle(_ a: NSPoint, _ b: NSPoint) -> NSPoint {
        let step = CGFloat.pi / 4
        let angle = (atan2(b.y - a.y, b.x - a.x) / step).rounded() * step
        let len = hypot(b.x - a.x, b.y - a.y)
        return NSPoint(x: a.x + len * cos(angle), y: a.y + len * sin(angle))
    }

    private static func snapSquare(_ a: NSPoint, _ b: NSPoint) -> NSPoint {
        let dx = b.x - a.x, dy = b.y - a.y
        let s = max(abs(dx), abs(dy))
        return NSPoint(x: a.x + (dx < 0 ? -s : s), y: a.y + (dy < 0 ? -s : s))
    }
}
