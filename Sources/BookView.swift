import Cocoa

enum ViewMode: Int {
    case three = 0, two, one
    var minSize: NSSize {
        switch self { case .three: return NSSize(width: 680, height: 420); case .two: return NSSize(width: 520, height: 380); case .one: return NSSize(width: 370, height: 340) }
    }
    var maxSize: NSSize {
        switch self { case .one: return NSSize(width: 560, height: 4000); default: return NSSize(width: 4000, height: 4000) }
    }
    var defaultSize: NSSize {
        switch self { case .three: return NSSize(width: 906, height: 516); case .two: return NSSize(width: 700, height: 516); case .one: return NSSize(width: 430, height: 437) }
    }
}

/// Geometry of the book, shared by drawing and by layout of the interactive subviews (all in view coordinates, flipped).
struct BookGeo {
    static let sideInset: CGFloat = 6.3, topInset: CGFloat = 7.5, bottomInset: CGFloat = 7
    static let edgeStripes: CGFloat = 12         // stacked page edges
    static let sidebarDivider: CGFloat = 149     // x of the sidebar | list line (3-pane)
    let bounds: NSRect, mode: ViewMode
    var pages: NSRect { NSRect(x: BookGeo.sideInset, y: BookGeo.topInset, width: bounds.width - 2 * BookGeo.sideInset, height: bounds.height - BookGeo.topInset - BookGeo.bottomInset) }
    var fold: CGFloat? { mode == .one ? nil : bounds.midX.rounded() }
    var leftPage: NSRect? { guard let f = fold else { return nil }; return NSRect(x: pages.minX, y: pages.minY, width: f - pages.minX, height: pages.height) }
    var rightPage: NSRect { guard let f = fold else { return pages }; return NSRect(x: f, y: pages.minY, width: pages.maxX - f, height: pages.height) }
}

final class BookView: NSView {
    var mode: ViewMode = .three { didSet { needsLayout = true; needsDisplay = true; window?.invalidateCursorRects(for: self) } }
    var geo: BookGeo { BookGeo(bounds: bounds, mode: mode) }
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var mouseDownCanMoveWindow: Bool { true }
    private(set) var lights: [NSButton] = []

    private static let grain: NSImage = {
        let n = 96
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: n, pixelsHigh: n, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        var s: UInt64 = 0x9E3779B97F4A7C15
        func rnd() -> Double { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return Double(s % 10000) / 10000 }
        var col = [Double](repeating: 0, count: n)
        for y in 0..<n {
            for x in 0..<n {
                if y % 3 == 0 { col[x] = col[x] * 0.6 + (rnd() - 0.5) * 0.8 }   // vertical streaks, like the wrapped cover
                let v = col[x] + (rnd() - 0.5) * 0.7
                let c = 0.0   // dark flecks only: a light overlay would wash out the leather
                rep.setColor(NSColor(deviceRed: c, green: c, blue: c, alpha: min(0.30, abs(v) * 0.30)), atX: x, y: y)
            }
        }
        let im = NSImage(size: NSSize(width: n, height: n)); im.addRepresentation(rep); return im
    }()

    override init(frame: NSRect) {
        super.init(frame: frame)
        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        for (i, t) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
            if let b = NSWindow.standardWindowButton(t, for: style) { b.tag = i; addSubview(b); lights.append(b) }
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        guard let w = window else { return }
        lights[0].target = w; lights[0].action = #selector(NSWindow.close)
        lights[1].target = w; lights[1].action = #selector(NSWindow.miniaturize(_:))
        lights[2].target = self; lights[2].action = #selector(zoom(_:))
        for b in lights { b.setAccessibilityElement(true) }
        NotificationCenter.default.addObserver(self, selector: #selector(keyChanged), name: NSWindow.didBecomeKeyNotification, object: w)
        NotificationCenter.default.addObserver(self, selector: #selector(keyChanged), name: NSWindow.didResignKeyNotification, object: w)
    }
    @objc func keyChanged() { needsDisplay = true; subviews.forEach { $0.needsDisplay = true }; window?.invalidateShadow() }
    @objc func zoom(_ s: Any?) { (window as? BookWindow)?.toggleZoom() }

    var onLayout: (() -> Void)?
    override func layout() {
        super.layout()
        onLayout?()
        var x: CGFloat = 32.6 - 7
        for b in lights { b.setFrameOrigin(NSPoint(x: x, y: 22 - b.frame.height / 2)); x += 20 }
    }

    // MARK: drawing (colours sampled from the Mountain Lion reference capture)

    private func g(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> NSColor { NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a) }
    private func lin(_ path: NSBezierPath, _ colors: [NSColor], from: NSPoint, to: NSPoint) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState(); path.addClip()
        let cg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors.map { $0.cgColor } as CFArray, locations: nil)!
        ctx.drawLinearGradient(cg, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }
    private func poly(_ p: [NSPoint]) -> NSBezierPath { let b = NSBezierPath(); b.move(to: p[0]); p.dropFirst().forEach { b.line(to: $0) }; b.close(); return b }

    override func draw(_ dirty: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let b = bounds, geo = self.geo, pr = geo.pages
        let o = b

        // --- leather rim: four bevelled strips, light on the outside, dark towards the pages
        let top = [g(225, 194, 147), g(211, 180, 134), g(208, 175, 126), g(201, 165, 115), g(196, 158, 105), g(192, 152, 96), g(187, 147, 88), g(182, 140, 80), g(177, 133, 70), g(172, 128, 63), g(168, 124, 62), g(155, 109, 44), g(149, 104, 43)]
        let left = [g(196, 157, 100), g(193, 153, 97), g(191, 151, 94), g(189, 148, 90), g(187, 145, 86), g(182, 140, 81), g(178, 135, 76), g(174, 130, 71), g(167, 124, 65), g(160, 118, 60), g(153, 112, 58), g(143, 103, 45), g(133, 93, 28)]
        let right = [g(196, 157, 100), g(193, 153, 97), g(191, 151, 94), g(189, 148, 90), g(187, 145, 86), g(182, 140, 81), g(178, 135, 76), g(174, 130, 71), g(167, 124, 65), g(160, 118, 60), g(153, 112, 58), g(143, 103, 45), g(133, 93, 28)]
        let bottom = [g(66, 32, 11), g(92, 70, 35), g(95, 67, 32), g(103, 73, 35), g(112, 78, 38), g(118, 82, 40), g(121, 83, 42), g(115, 75, 38), g(107, 68, 35), g(98, 62, 33), g(92, 56, 29), g(79, 48, 29)]
        let oTL = NSPoint(x: o.minX, y: o.minY), oTR = NSPoint(x: o.maxX, y: o.minY), oBL = NSPoint(x: o.minX, y: o.maxY), oBR = NSPoint(x: o.maxX, y: o.maxY)
        let pTL = NSPoint(x: pr.minX, y: pr.minY), pTR = NSPoint(x: pr.maxX, y: pr.minY), pBL = NSPoint(x: pr.minX, y: pr.maxY), pBR = NSPoint(x: pr.maxX, y: pr.maxY)
        lin(poly([oTL, oTR, pTR, pTL]), top, from: NSPoint(x: 0, y: o.minY), to: NSPoint(x: 0, y: pr.minY))
        lin(poly([oTL, pTL, pBL, oBL]), left, from: NSPoint(x: o.minX, y: 0), to: NSPoint(x: pr.minX, y: 0))
        lin(poly([oTR, pTR, pBR, oBR]), right.reversed(), from: NSPoint(x: pr.maxX, y: 0), to: NSPoint(x: o.maxX, y: 0))
        lin(poly([oBL, oBR, pBR, pBL]), bottom, from: NSPoint(x: 0, y: pr.maxY), to: NSPoint(x: 0, y: o.maxY))
        // grain (cached tile, never stretched)
        ctx.saveGState()
        let rim = NSBezierPath(rect: o); rim.append(NSBezierPath(rect: pr)); rim.windingRule = .evenOdd; rim.addClip()
        let tile = BookView.grain, ts = tile.size
        var ty = o.minY
        while ty < o.maxY { var tx = o.minX; while tx < o.maxX { tile.draw(in: NSRect(x: tx, y: ty, width: ts.width, height: ts.height), from: .zero, operation: .sourceOver, fraction: 0.35, respectFlipped: true, hints: nil); tx += ts.width }; ty += ts.height }
        ctx.restoreGState()
        

        // --- pages
        func white(_ v: Int) -> NSColor { NSColor.sg(CGFloat(v) / 255, 1) }
        let st = BookGeo.edgeStripes
        if let lp = geo.leftPage, let f = geo.fold {
            let rp = geo.rightPage
            white(247).setFill(); lp.fill()
            if mode == .three {
                white(255).setFill(); NSRect(x: BookGeo.sidebarDivider + 1, y: lp.minY, width: f - BookGeo.sidebarDivider - 1, height: lp.height).fill()
                white(229).setFill(); NSRect(x: BookGeo.sidebarDivider, y: lp.minY, width: 1, height: lp.height).fill()
            } else { white(255).setFill(); NSRect(x: lp.minX + st, y: lp.minY, width: lp.width - st, height: lp.height).fill() }
            // soft shading into the binding
            NSGradient(colors: [white(255), white(242), white(222)], atLocations: [0, 0.5, 1], colorSpace: .deviceRGB)!.draw(in: NSRect(x: f - 40, y: lp.minY, width: 40, height: lp.height), angle: 0)
            white(255).setFill(); rp.fill()
            NSGradient(colors: [white(224), white(238), white(255)], atLocations: [0, 0.45, 1], colorSpace: .deviceRGB)!.draw(in: NSRect(x: f, y: rp.minY, width: 40, height: rp.height), angle: 0)
            white(172).setFill(); NSRect(x: f - 0.6, y: pr.minY, width: 1.2, height: pr.height).fill()
            // binding stitches: four slim threads on the fold (light core, dark outline, fine twist marks)
            for k in 0..<4 {
                let y = pr.minY + pr.height * (0.079 + 0.25 * CGFloat(k))
                let bar = NSBezierPath(roundedRect: NSRect(x: f - 1.3, y: y, width: 2.6, height: 44), xRadius: 1.3, yRadius: 1.3)
                white(214).setFill(); bar.fill()
                ctx.saveGState(); bar.addClip(); white(160).setFill()
                var t = y + 2; while t < y + 43 { NSRect(x: f - 1.3, y: t, width: 2.6, height: 0.6).fill(); t += 1.6 }
                ctx.restoreGState()
                white(105).setStroke(); bar.lineWidth = 0.6; bar.stroke()
            }
            drawStripes(NSRect(x: lp.minX, y: lp.minY, width: st, height: lp.height), outer: .left)
            drawStripes(NSRect(x: rp.maxX - st, y: rp.minY, width: st, height: rp.height), outer: .right)
        } else {
            white(255).setFill(); pr.fill()
            drawStripes(NSRect(x: pr.minX, y: pr.minY, width: st, height: pr.height), outer: .left)
            drawStripes(NSRect(x: pr.maxX - st, y: pr.minY, width: st, height: pr.height), outer: .right)
        }

        // --- clasp straps
        let cx = geo.fold ?? b.midX
        func strap(_ r: NSRect, flip: Bool) {
            let p = NSBezierPath(roundedRect: r, xRadius: 2, yRadius: 2)
            let cols = [g(94, 69, 42), g(80, 55, 31), g(80, 55, 31), g(76, 52, 29), g(54, 28, 15)]
            lin(p, flip ? cols.reversed() : cols, from: NSPoint(x: 0, y: r.minY), to: NSPoint(x: 0, y: r.maxY))
            ctx.saveGState(); p.addClip(); tile.draw(in: r, from: .zero, operation: .sourceOver, fraction: 0.6, respectFlipped: true, hints: nil); ctx.restoreGState()
            g(40, 22, 6, 0.8).setStroke(); p.lineWidth = 0.8; p.stroke()
        }
        strap(NSRect(x: cx - 46, y: 0, width: 92, height: BookGeo.topInset), flip: false)
        strap(NSRect(x: cx - 46, y: b.height - BookGeo.bottomInset, width: 92, height: BookGeo.bottomInset), flip: true)
    }

    private enum Side { case left, right }
    private func drawStripes(_ r: NSRect, outer: Side) {
        // alternating grey/white hairlines, getting lighter towards the page
        let vals: [CGFloat] = outer == .left ? [174, 165, 201, 174, 219, 214, 190, 234, 234, 218, 208, 250] : [250, 202, 222, 236, 220, 194, 218, 206, 178, 206, 158, 180]
        let w = r.width / CGFloat(vals.count)
        for (i, v) in vals.enumerated() {
            NSColor.sg(v / 255, 1).setFill()
            NSRect(x: r.minX + CGFloat(i) * w, y: r.minY, width: w + 0.3, height: r.height).fill()
        }
    }

    // MARK: resizing (the window is borderless, so the book's leather rim acts as the frame)

    private enum Edge { case l, r, t, b }
    private func edges(at p: NSPoint) -> Set<Edge> {
        var s = Set<Edge>(); let w: CGFloat = 7
        if p.x < w { s.insert(.l) }; if p.x > bounds.width - w { s.insert(.r) }
        if p.y < 5 { s.insert(.t) }; if p.y > bounds.height - 5 { s.insert(.b) }
        return s
    }
    override func resetCursorRects() {
        let w: CGFloat = 7, c: CGFloat = 14
        addCursorRect(NSRect(x: 0, y: c, width: w, height: bounds.height - 2 * c), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: bounds.width - w, y: c, width: w, height: bounds.height - 2 * c), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: c, y: 0, width: bounds.width - 2 * c, height: 5), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: c, y: bounds.height - 5, width: bounds.width - 2 * c, height: 5), cursor: .resizeUpDown)
        let diag: NSCursor = NSCursor.crosshair
        for r in [NSRect(x: 0, y: 0, width: c, height: c), NSRect(x: bounds.width - c, y: 0, width: c, height: c),
                  NSRect(x: 0, y: bounds.height - c, width: c, height: c), NSRect(x: bounds.width - c, y: bounds.height - c, width: c, height: c)] {
            addCursorRect(r, cursor: diag)
        }
    }
    override func mouseDown(with e: NSEvent) {
        guard let win = window else { return }
        var ed = edges(at: convert(e.locationInWindow, from: nil))
        let p = convert(e.locationInWindow, from: nil)
        if !ed.isEmpty {   // corners are 14pt zones
            let c: CGFloat = 14
            ed = []
            if p.x < 7 || (p.x < c && (p.y < c || p.y > bounds.height - c)) { ed.insert(.l) }
            if p.x > bounds.width - 7 || (p.x > bounds.width - c && (p.y < c || p.y > bounds.height - c)) { ed.insert(.r) }
            if p.y < 5 || (p.y < c && (p.x < c || p.x > bounds.width - c)) { ed.insert(.t) }
            if p.y > bounds.height - 5 || (p.y > bounds.height - c && (p.x < c || p.x > bounds.width - c)) { ed.insert(.b) }
        }
        if ed.isEmpty { super.mouseDown(with: e); return }
        let start = NSEvent.mouseLocation, f0 = win.frame
        let minS = win.minSize, maxS = win.maxSize
        while let ev = win.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if ev.type == .leftMouseUp { break }
            let m = NSEvent.mouseLocation, dx = m.x - start.x, dy = m.y - start.y
            var f = f0
            if ed.contains(.r) { f.size.width = min(max(f0.width + dx, minS.width), maxS.width) }
            if ed.contains(.l) { let w = min(max(f0.width - dx, minS.width), maxS.width); f.origin.x = f0.maxX - w; f.size.width = w }
            if ed.contains(.b) { let h = min(max(f0.height - dy, minS.height), maxS.height); f.origin.y = f0.maxY - h; f.size.height = h }
            if ed.contains(.t) { f.size.height = min(max(f0.height + dy, minS.height), maxS.height) }
            win.setFrame(f, display: true)
        }
    }
}

/// Borderless window: real system traffic lights live inside the book, resizing and zooming are handled here.
final class BookWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    var restoreFrame: NSRect?

    /// minSize/maxSize are only honoured by the system for titled windows, so every programmatic frame change is clamped here
    private func clamped(_ f: NSRect) -> NSRect {
        var r = f
        r.size.width = min(max(f.width, minSize.width), maxSize.width); r.size.height = min(max(f.height, minSize.height), maxSize.height)
        r.origin.y = f.maxY - r.height
        return r
    }
    override func setFrame(_ f: NSRect, display d: Bool) { super.setFrame(clamped(f), display: d) }
    override func setFrame(_ f: NSRect, display d: Bool, animate a: Bool) { super.setFrame(clamped(f), display: d, animate: a) }

    func toggleZoom() {
        if let r = restoreFrame { setFrame(r, display: true, animate: true); restoreFrame = nil; return }
        restoreFrame = frame
        let vis = screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        var w = min(vis.width, maxSize.width), h = min(vis.height, maxSize.height)
        if (contentView as? BookView)?.mode == .one { w = min(w, 460); h = vis.height }
        else { w = min(w, 1100); h = min(h, 760) }
        let nf = NSRect(x: frame.midX - w / 2, y: vis.maxY - h, width: w, height: h)
        setFrame(nf.intersection(vis).isEmpty ? nf : NSRect(x: max(vis.minX, min(nf.minX, vis.maxX - w)), y: nf.minY, width: w, height: h), display: true, animate: true)
    }
}
