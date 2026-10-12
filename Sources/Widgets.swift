import Cocoa

// MARK: - Fonts / colours (Mountain Lion used Lucida Grande throughout)

enum Fonts {
    static func regular(_ s: CGFloat) -> NSFont { NSFont(name: "LucidaGrande", size: s) ?? .systemFont(ofSize: s) }
    static func bold(_ s: CGFloat) -> NSFont { NSFont(name: "LucidaGrande-Bold", size: s) ?? .boldSystemFont(ofSize: s) }
}

enum Pal {
    static let labelGrey = NSColor(calibratedWhite: 0.55, alpha: 1)
    static let selBlueText = NSColor(calibratedRed: 0.31, green: 0.43, blue: 0.61, alpha: 1)
    static let selPale = NSColor(calibratedRed: 0.935, green: 0.950, blue: 0.985, alpha: 1)
    static let link = NSColor(calibratedRed: 0.06, green: 0.20, blue: 0.82, alpha: 1)
    static let sideBlue = NSColor(calibratedRed: 0.35, green: 0.45, blue: 0.65, alpha: 1)
    static let line = NSColor(calibratedWhite: 0.62, alpha: 1)
}

func gradient(_ c: [NSColor]) -> NSGradient { NSGradient(colors: c)! }

// MARK: - Push button in the Mountain Lion "small gradient" style

class RetroButton: NSControl {
    var title = "" { didSet { needsDisplay = true } }
    var glyph: ((NSRect, NSColor) -> Void)?
    var pressed = false { didSet { needsDisplay = true } }
    var titleColor: NSColor? { didSet { needsDisplay = true } }
    var segmentPosition: (first: Bool, last: Bool) = (true, true)
    var selectedLook = false { didSet { needsDisplay = true } }
    var popUpMenu: (() -> NSMenu?)?
    override var isEnabled: Bool { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    convenience init(title: String = "", glyph: ((NSRect, NSColor) -> Void)? = nil) {
        self.init(frame: .zero); self.title = title; self.glyph = glyph
        setAccessibilityRole(.button); setAccessibilityLabel(title)
    }

    override func draw(_ dirty: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let rad: CGFloat = 5
        let active = window?.isKeyWindow ?? true
        let path: NSBezierPath
        if segmentPosition.first && segmentPosition.last { path = NSBezierPath(roundedRect: r, xRadius: rad, yRadius: rad) }
        else {
            let rr = r.insetBy(dx: segmentPosition.first ? 0 : -rad, dy: 0).offsetBy(dx: segmentPosition.first ? 0 : 0, dy: 0)
            var rect = r
            if !segmentPosition.first { rect.origin.x -= rad; rect.size.width += rad }
            if !segmentPosition.last { rect.size.width += rad }
            _ = rr
            path = NSBezierPath(roundedRect: rect, xRadius: rad, yRadius: rad)
        }
        NSGraphicsContext.saveGraphicsState()
        // drop shadow line below
        clipBox()?.addClip()
        let dark = pressed || selectedLook
        let g: NSGradient = dark
            ? gradient([NSColor(calibratedWhite: pressed ? 0.80 : 0.88, alpha: 1), NSColor(calibratedWhite: pressed ? 0.88 : 0.95, alpha: 1)])
            : gradient([NSColor(calibratedWhite: 1.0, alpha: 1), NSColor(calibratedWhite: 0.985, alpha: 1), NSColor(calibratedWhite: 0.955, alpha: 1), NSColor(calibratedWhite: 0.965, alpha: 1)])
        g.draw(in: path, angle: -90)
        NSGraphicsContext.restoreGraphicsState()
        NSColor(calibratedWhite: active ? 0.80 : 0.86, alpha: 1).setStroke()
        path.lineWidth = 1
        if segmentPosition.first && segmentPosition.last { path.stroke() }
        else {
            NSGraphicsContext.saveGraphicsState(); clipBox()?.addClip(); path.stroke(); NSGraphicsContext.restoreGraphicsState()
        }
        let ink = NSColor(calibratedWhite: isEnabled ? 0.22 : 0.70, alpha: 1)
        if let glyph = glyph { glyph(bounds, ink) }
        else if !title.isEmpty {
            let a: [NSAttributedString.Key: Any] = [.font: Fonts.regular(11), .foregroundColor: isEnabled ? (titleColor ?? ink) : ink]
            let s = NSAttributedString(string: title, attributes: a)
            let sz = s.size()
            s.draw(at: NSPoint(x: (bounds.width - sz.width) / 2, y: (bounds.height - sz.height) / 2 + 0.5))
        }
    }

    private func clipBox() -> NSBezierPath? { NSBezierPath(rect: bounds) }

    override func mouseDown(with e: NSEvent) {
        guard isEnabled else { return }
        pressed = true
        if let m = popUpMenu?() {
            pressed = true
            m.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + 2), in: self)
            pressed = false; return
        }
        var inside = true
        while let ev = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
            inside = bounds.contains(convert(ev.locationInWindow, from: nil))
            pressed = inside
            if ev.type == .leftMouseUp { break }
        }
        pressed = false
        if inside { sendAction(action, to: target) }
    }
    override func accessibilityPerformPress() -> Bool { if isEnabled { sendAction(action, to: target) }; return true }
}

// glyph helpers
enum Glyph {
    static func plus(_ r: NSRect, _ c: NSColor) {
        c.setStroke(); let p = NSBezierPath(); p.lineWidth = 1.6
        p.move(to: NSPoint(x: r.midX - 4, y: r.midY)); p.line(to: NSPoint(x: r.midX + 4, y: r.midY))
        p.move(to: NSPoint(x: r.midX, y: r.midY - 4)); p.line(to: NSPoint(x: r.midX, y: r.midY + 4)); p.stroke()
    }
    static func triangle(left: Bool) -> (NSRect, NSColor) -> Void {
        return { r, c in
            c.setFill(); let s: CGFloat = left ? -1 : 1
            let p = NSBezierPath(); p.move(to: NSPoint(x: r.midX + 3 * s, y: r.midY - 4)); p.line(to: NSPoint(x: r.midX - 3 * s, y: r.midY)); p.line(to: NSPoint(x: r.midX + 3 * s, y: r.midY + 4)); p.close(); p.fill()
        }
    }
    static func chevron(left: Bool) -> (NSRect, NSColor) -> Void {
        return { r, c in
            c.setStroke(); let p = NSBezierPath(); p.lineWidth = 1.8; p.lineCapStyle = .round; p.lineJoinStyle = .round
            let s: CGFloat = left ? -1 : 1
            p.move(to: NSPoint(x: r.midX - 2 * s, y: r.midY - 4)); p.line(to: NSPoint(x: r.midX + 2 * s, y: r.midY)); p.line(to: NSPoint(x: r.midX - 2 * s, y: r.midY + 4)); p.stroke()
        }
    }
    static func share(_ r: NSRect, _ c: NSColor) {     // arrow leaving a box
        c.setStroke(); c.setFill()
        let box = NSBezierPath(); box.lineWidth = 1.1
        let x0 = r.midX - 6, y0 = r.midY - 4.5
        box.move(to: NSPoint(x: x0 + 5, y: y0 + 2)); box.line(to: NSPoint(x: x0, y: y0 + 2)); box.line(to: NSPoint(x: x0, y: y0 + 11)); box.line(to: NSPoint(x: x0 + 11, y: y0 + 11)); box.line(to: NSPoint(x: x0 + 11, y: y0 + 8)); box.stroke()
        let a = NSBezierPath(); a.lineWidth = 1.3
        a.move(to: NSPoint(x: x0 + 3, y: y0 + 8)); a.curve(to: NSPoint(x: x0 + 10, y: y0 + 3), controlPoint1: NSPoint(x: x0 + 4, y: y0 + 4), controlPoint2: NSPoint(x: x0 + 7, y: y0 + 3)); a.stroke()
        let h = NSBezierPath(); h.move(to: NSPoint(x: x0 + 9, y: y0 - 0.5)); h.line(to: NSPoint(x: x0 + 14, y: y0 + 3.2)); h.line(to: NSPoint(x: x0 + 9, y: y0 + 6.4)); h.close(); h.fill()
    }
    /// view-mode icons: n = 0 (3-pane), 1 (2-pane), 2 (card only)
    static func viewMode(_ n: Int) -> (NSRect, NSColor) -> Void {
        return { r, c in
            c.setStroke(); c.setFill()
            func lines(_ x: CGFloat, _ w: CGFloat) {
                for i in 0..<3 { NSBezierPath(rect: NSRect(x: x, y: r.midY - 4 + CGFloat(i) * 3.4, width: w, height: 1.4)).fill() }
            }
            func box(_ x: CGFloat) { let p = NSBezierPath(roundedRect: NSRect(x: x, y: r.midY - 4.5, width: 6.5, height: 9), xRadius: 1, yRadius: 1); p.lineWidth = 1.2; p.stroke() }
            switch n {
            case 0: lines(r.midX - 9.5, 3); lines(r.midX - 4.5, 4.5); box(r.midX + 3)
            case 1: lines(r.midX - 8, 6); box(r.midX + 1.5)
            default: box(r.midX - 3.2)
            }
        }
    }
}

final class RetroSegmented: NSView {
    var buttons: [RetroButton] = []
    var onSelect: ((Int) -> Void)?
    var selected = 0 { didSet { for (i, b) in buttons.enumerated() { b.selectedLook = i == selected } } }
    override var isFlipped: Bool { true }
    init(glyphs: [(NSRect, NSColor) -> Void]) {
        super.init(frame: .zero)
        for (i, g) in glyphs.enumerated() {
            let b = RetroButton(glyph: g); b.tag = i
            b.segmentPosition = (i == 0, i == glyphs.count - 1)
            b.target = self; b.action = #selector(hit(_:))
            b.setAccessibilityLabel([L("Gruppen, Liste und Karte", "Groups, list and card"), L("Liste und Karte", "List and card"), L("Nur Karte", "Card only")][i])
            addSubview(b); buttons.append(b)
        }
        selected = 0
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc func hit(_ b: RetroButton) { selected = b.tag; onSelect?(b.tag) }
    override func layout() {
        super.layout()
        let w = bounds.width / CGFloat(buttons.count)
        for (i, b) in buttons.enumerated() { b.frame = NSRect(x: (w * CGFloat(i)).rounded(), y: 0, width: (w * CGFloat(i + 1)).rounded() - (w * CGFloat(i)).rounded(), height: bounds.height) }
    }
}

// MARK: - Search field (capsule, as in Mountain Lion)

final class RetroSearchField: NSView, NSTextFieldDelegate {
    let field = NSTextField()
    var onChange: ((String) -> Void)?
    var text: String { get { field.stringValue } set { field.stringValue = newValue; needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    var focused = false { didSet { needsDisplay = true } }
    var count: Int? { didSet { needsDisplay = true; needsLayout = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        field.isBordered = false; field.drawsBackground = false; field.focusRingType = .none
        field.font = Fonts.regular(11); field.delegate = self
        field.cell?.usesSingleLineMode = true; field.cell?.isScrollable = true
        field.setAccessibilityLabel(L("Suchen", "Search"))
        addSubview(field)
        setAccessibilityRole(.group)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); field.frame = NSRect(x: 20, y: (bounds.height - 15) / 2 + 0.5, width: bounds.width - 40 - (count == nil ? 0 : 52), height: 15) }
    func controlTextDidChange(_ n: Notification) { needsDisplay = true; onChange?(field.stringValue) }
    func controlTextDidBeginEditing(_ obj: Notification) { focused = true }
    func controlTextDidEndEditing(_ obj: Notification) { focused = false }
    override func mouseDown(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        if !field.stringValue.isEmpty && p.x > bounds.width - 20 { field.stringValue = ""; onChange?(""); needsDisplay = true }
        else { window?.makeFirstResponder(field) }
    }
    override func draw(_ dirty: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let p = NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2)
                NSColor.white.setFill(); p.fill()
        NSGraphicsContext.saveGraphicsState(); p.addClip()
        gradient([NSColor(calibratedWhite: 0.86, alpha: 1), NSColor(calibratedWhite: 1, alpha: 0)]).draw(in: NSRect(x: 0, y: 0, width: bounds.width, height: 3), angle: -90)
        NSGraphicsContext.restoreGraphicsState()
        (focused ? NSColor(calibratedRed: 0.35, green: 0.55, blue: 0.85, alpha: 1) : NSColor(calibratedWhite: 0.76, alpha: 1)).setStroke(); p.lineWidth = 1; p.stroke()
        // magnifier
        let c = NSColor(calibratedWhite: 0.40, alpha: 1); c.setStroke()
        let m = NSBezierPath(ovalIn: NSRect(x: 7, y: bounds.midY - 5, width: 7, height: 7)); m.lineWidth = 1.3; m.stroke()
        let h = NSBezierPath(); h.lineWidth = 1.6; h.lineCapStyle = .round; h.move(to: NSPoint(x: 13, y: bounds.midY + 1.5)); h.line(to: NSPoint(x: 16, y: bounds.midY + 4.5)); h.stroke()
        if let n = count {
            let s = NSAttributedString(string: L("\(n) gefunden", "\(n) Found"), attributes: [.font: Fonts.regular(10), .foregroundColor: NSColor(calibratedWhite: 0.45, alpha: 1)])
            s.draw(at: NSPoint(x: bounds.width - 20 - s.size().width, y: (bounds.height - s.size().height) / 2))
        }
        if !field.stringValue.isEmpty {
            let cx = bounds.width - 10, cy = bounds.midY
            NSColor(calibratedWhite: 0.62, alpha: 1).setFill(); NSBezierPath(ovalIn: NSRect(x: cx - 4.5, y: cy - 4.5, width: 9, height: 9)).fill()
            NSColor.white.setStroke(); let x = NSBezierPath(); x.lineWidth = 1.3
            x.move(to: NSPoint(x: cx - 2, y: cy - 2)); x.line(to: NSPoint(x: cx + 2, y: cy + 2)); x.move(to: NSPoint(x: cx + 2, y: cy - 2)); x.line(to: NSPoint(x: cx - 2, y: cy + 2)); x.stroke()
        }
    }
}

// MARK: - Contact photo (placeholder silhouette, framed)

final class PhotoView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    var editable = false { didSet { needsDisplay = true } }
    var onChange: ((Data?) -> Void)?
    override var isFlipped: Bool { true }
    override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([.fileURL, .tiff, .png]) }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirty: NSRect) {
        var r = bounds.insetBy(dx: 0.5, dy: 0.5)
        if editable {   // white mat with drop shadow while editing
            NSGraphicsContext.saveGraphicsState()
            let sh = NSShadow(); sh.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.35); sh.shadowOffset = NSSize(width: 0, height: -1.5); sh.shadowBlurRadius = 2.5; sh.set()
            NSColor.white.setFill(); NSBezierPath(rect: r).fill(); NSGraphicsContext.restoreGraphicsState()
            NSColor(calibratedWhite: 0.7, alpha: 1).setStroke(); NSBezierPath(rect: r).stroke()
            r = r.insetBy(dx: 3, dy: 3)
        }
        let clip = NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3)
        NSGraphicsContext.saveGraphicsState(); clip.addClip()
        if let img = image {
            let s = img.size; let k = max(r.width / s.width, r.height / s.height)
            let w = s.width * k, h = s.height * k
            img.draw(in: NSRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        } else {
            gradient([NSColor(calibratedWhite: 0.93, alpha: 1), NSColor(calibratedWhite: 0.80, alpha: 1)]).draw(in: r, angle: 90)
            NSColor(calibratedWhite: 0.62, alpha: 1).setFill()
            let w = r.width
            NSBezierPath(ovalIn: NSRect(x: r.midX - w * 0.17, y: r.minY + w * 0.18, width: w * 0.34, height: w * 0.38)).fill()
            NSBezierPath(ovalIn: NSRect(x: r.midX - w * 0.38, y: r.minY + w * 0.62, width: w * 0.76, height: w * 0.7)).fill()
        }
        if editable && bounds.width >= 44 {
            let a: [NSAttributedString.Key: Any] = [.font: Fonts.regular(10), .foregroundColor: NSColor.white]
            let t = NSAttributedString(string: L("ändern", "edit"), attributes: a); let sz = t.size()
            NSColor(calibratedWhite: 0.42, alpha: 1).setFill()
            NSBezierPath(rect: NSRect(x: r.minX, y: r.maxY - 15, width: r.width, height: 15)).fill()
            t.draw(at: NSPoint(x: r.midX - sz.width / 2, y: r.maxY - 14))
        }
        NSGraphicsContext.restoreGraphicsState()
        NSColor(calibratedWhite: 0.45, alpha: 0.9).setStroke(); clip.lineWidth = 1; clip.stroke()
        NSColor(calibratedWhite: 1, alpha: 0.30).setStroke(); let inner = NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 1), xRadius: 2, yRadius: 2); inner.lineWidth = 1; inner.stroke()
    }

    private func set(_ img: NSImage?) {
        guard let img = img else { image = nil; onChange?(nil); return }
        // limit to 512 px, store as JPEG
        let k = min(1, 512 / max(img.size.width, img.size.height))
        let sz = NSSize(width: img.size.width * k, height: img.size.height * k)
        let out = NSImage(size: sz); out.lockFocus(); img.draw(in: NSRect(origin: .zero, size: sz)); out.unlockFocus()
        guard let t = out.tiffRepresentation, let rep = NSBitmapImageRep(data: t), let d = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else { return }
        image = NSImage(data: d); onChange?(d)
    }

    override func mouseDown(with e: NSEvent) {
        guard editable else { return }
        let m = NSMenu()
        m.addItem(withTitle: L("Bild wählen …", "Choose Picture…"), action: #selector(choose), keyEquivalent: "").target = self
        let rm = m.addItem(withTitle: L("Bild entfernen", "Remove Picture"), action: #selector(remove), keyEquivalent: ""); rm.target = self; rm.isEnabled = image != nil
        m.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height), in: self)
    }
    @objc func choose() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.image]
        if p.runModal() == .OK, let u = p.url { set(NSImage(contentsOf: u)) }
    }
    @objc func remove() { set(nil) }
    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation { editable ? .copy : [] }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool {
        guard editable, let img = NSImage(pasteboard: s.draggingPasteboard) else { return false }
        set(img); return true
    }
}
