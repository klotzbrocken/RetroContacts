import Cocoa
import Contacts

// MARK: - small controls

final class RoundIconButton: NSControl {
    enum Kind { case minus, plus }
    var kind: Kind = .minus
    var pressed = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    convenience init(_ k: Kind) { self.init(frame: NSRect(x: 0, y: 0, width: 13, height: 13)); kind = k; setAccessibilityRole(.button); setAccessibilityLabel(k == .minus ? L("Entfernen", "Remove") : L("Hinzufügen", "Add")) }
    override func draw(_ r: NSRect) {
        let o = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.8, dy: 0.8))
        let (a, b, e): (NSColor, NSColor, NSColor) = kind == .minus
            ? (NSColor(srgbRed: 0.98, green: 0.52, blue: 0.48, alpha: 1), NSColor(srgbRed: 0.80, green: 0.14, blue: 0.12, alpha: 1), NSColor(srgbRed: 0.55, green: 0.08, blue: 0.06, alpha: 1))
            : (NSColor(srgbRed: 0.55, green: 0.85, blue: 0.45, alpha: 1), NSColor(srgbRed: 0.20, green: 0.60, blue: 0.14, alpha: 1), NSColor(srgbRed: 0.10, green: 0.40, blue: 0.06, alpha: 1))
        gradient(pressed ? [b, b] : [a, b]).draw(in: o, angle: -90)
        e.setStroke(); o.lineWidth = 1; o.stroke()
        NSColor.white.setStroke(); let p = NSBezierPath(); p.lineWidth = 1.6
        p.move(to: NSPoint(x: bounds.midX - 2.8, y: bounds.midY)); p.line(to: NSPoint(x: bounds.midX + 2.8, y: bounds.midY))
        if kind == .plus { p.move(to: NSPoint(x: bounds.midX, y: bounds.midY - 2.8)); p.line(to: NSPoint(x: bounds.midX, y: bounds.midY + 2.8)) }
        p.stroke()
    }
    override func mouseDown(with e: NSEvent) {
        pressed = true
        while let ev = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
            pressed = bounds.contains(convert(ev.locationInWindow, from: nil)); if ev.type == .leftMouseUp { break }
        }
        let hit = pressed; pressed = false
        if hit { sendAction(action, to: target) }
    }
}

/// flat, square 1px-bordered field (the system bezel would turn into a rounded pill)
final class PaddedCell: NSTextFieldCell {
    override func drawingRect(forBounds r: NSRect) -> NSRect {
        var d = super.drawingRect(forBounds: r).insetBy(dx: 4, dy: 0)
        let th = ceil((font?.ascender ?? 11) - (font?.descender ?? -3) + (font?.leading ?? 0))
        d.origin.y += (d.height - th) / 2; d.size.height = th; return d
    }
    override func edit(withFrame r: NSRect, in v: NSView, editor t: NSText, delegate d: Any?, event e: NSEvent?) { super.edit(withFrame: drawingRect(forBounds: r), in: v, editor: t, delegate: d, event: e) }
    override func select(withFrame r: NSRect, in v: NSView, editor t: NSText, delegate d: Any?, start s: Int, length l: Int) { super.select(withFrame: drawingRect(forBounds: r), in: v, editor: t, delegate: d, start: s, length: l) }
}
final class EditField: NSTextField {
    var onText: ((String) -> Void)?
    override var mouseDownCanMoveWindow: Bool { false }
    override class var cellClass: AnyClass? { get { PaddedCell.self } set {} }
}

/// Grey label to the left of a value. Clicking opens the action menu (copy, large type, …).
final class FieldLabel: NSView {
    var text = ""; var menuProvider: (() -> NSMenu?)?
    var hover = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func draw(_ r: NSRect) {
        let a: [NSAttributedString.Key: Any] = [.font: Fonts.regular(11), .foregroundColor: hover ? NSColor.sg(0.25, 1) : Pal.labelGrey]
        let s = NSAttributedString(string: text, attributes: a); let sz = s.size()
        s.draw(at: NSPoint(x: bounds.width - sz.width - (hover && menuProvider != nil ? 11 : 0), y: 1.5))
        if hover && menuProvider != nil {
            let c = NSPoint(x: bounds.width - 5, y: 7)
            NSColor.sg(0.3, 1).setFill()
            let t = NSBezierPath(); t.move(to: NSPoint(x: c.x - 3, y: c.y - 1.5)); t.line(to: NSPoint(x: c.x + 3, y: c.y - 1.5)); t.line(to: NSPoint(x: c.x, y: c.y + 2)); t.close(); t.fill()
        }
    }
    override func updateTrackingAreas() { super.updateTrackingAreas(); trackingAreas.forEach(removeTrackingArea); addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self)) }
    override func mouseEntered(with e: NSEvent) { hover = true }
    override func mouseExited(with e: NSEvent) { hover = false }
    override func mouseDown(with e: NSEvent) { menuProvider?()?.popUp(positioning: nil, at: NSPoint(x: bounds.width - 6, y: bounds.height + 2), in: self) }
}

final class DottedLine: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ r: NSRect) {
        NSColor.sg(0.66, 1).setFill()
        var x: CGFloat = 0
        while x < bounds.width { NSRect(x: x, y: 0, width: 1, height: 1).fill(); x += 3 }
    }
}

final class FlippedView: NSView { override var isFlipped: Bool { true } }

final class LinkLabel: NSTextField {
    var onClick: (() -> Void)?
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func mouseDown(with e: NSEvent) { onClick?() }
}

func largeType(_ s: String) {
    let f = NSFont.systemFont(ofSize: 72, weight: .regular)
    let a: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: NSColor.white]
    let sz = (s as NSString).size(withAttributes: a)
    let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
    let w = min(screen.width - 60, sz.width + 80), h = sz.height + 50
    let p = BigPanel(contentRect: NSRect(x: screen.midX - w / 2, y: screen.midY - h / 2, width: w, height: h), styleMask: [.borderless], backing: .buffered, defer: false)
    p.isOpaque = false; p.backgroundColor = .clear; p.level = .floating; p.hasShadow = true
    let v = LargeTypeView(frame: NSRect(x: 0, y: 0, width: w, height: h)); v.text = NSAttributedString(string: s, attributes: a)
    p.contentView = v; p.makeKeyAndOrderFront(nil); p.isReleasedWhenClosed = false
    NSApp.activate(ignoringOtherApps: true)
    objc_setAssociatedObject(NSApp, "largeType", p, .OBJC_ASSOCIATION_RETAIN)
}
final class BigPanel: NSPanel { override var canBecomeKey: Bool { true }
    override func resignKey() { super.resignKey(); orderOut(nil) }
    override func keyDown(with e: NSEvent) { orderOut(nil) } }
final class LargeTypeView: NSView {
    var text = NSAttributedString()
    override func draw(_ r: NSRect) {
        let p = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 16, yRadius: 16)
        NSColor.sg(0.08, 0.92).setFill(); p.fill()
        let s = text.size(); text.draw(at: NSPoint(x: (bounds.width - s.width) / 2, y: (bounds.height - s.height) / 2))
    }
    override func mouseDown(with e: NSEvent) { window?.orderOut(nil) }
}

// MARK: - the card

final class CardView: NSView, NSTextFieldDelegate, NSTextViewDelegate {
    let scroll: NSScrollView
    let doc = FlippedView()
    var person: Person? { didSet { if !editing { rebuild() } } }
    var draft = Person(id: "")
    var draftNote = ""
    var editing = false
    var onStructure: (() -> Void)?
    var placeholder = "" { didSet { rebuild() } }
    private var lastWidth: CGFloat = 0
    private var firstFieldToFocus: NSView?

    // Metrics measured on a 3x capture of the original (906 pt wide window): the photo/field block is centred on the right page,
    // labels end at the photo's right edge, values start 9 pt further. `compact` = card-only window.
    static let labelW: CGFloat = 72
    var compact = false { didSet { rebuild() } }
    var highlight = "" { didSet { if !editing { rebuild() } } }
    var photoSize: CGFloat { compact ? 36 : 47 }
    var photoY: CGFloat { compact ? 44 : 38.5 }
    var photoX: CGFloat = 0, labelRight: CGFloat = 0, valueX: CGFloat = 0
    var areaX: CGFloat { labelRight - CardView.labelW }
    var sepX: CGFloat { compact ? 35 : 30 }
    var rightMargin: CGFloat { compact ? 58 : 37 }
    func layoutMetrics(_ w: CGFloat) {
        photoX = compact ? 74 : max(24, ((w - 217) / 2).rounded())
        labelRight = compact ? 123 : photoX + photoSize
        valueX = labelRight + 9
    }
    static let lineH: CGFloat = 16.5
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        scroll = retroScroll(doc)
        super.init(frame: frame)
        addSubview(scroll)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        scroll.frame = bounds
        if abs(bounds.width - lastWidth) > 0.5 { lastWidth = bounds.width; rebuild() }
    }

    // MARK: display mode

    func rebuild() {
        var keepFocusTag = 0
        if let ed = window?.firstResponder as? NSTextView, let f = ed.delegate as? NSView, f.isDescendant(of: doc) { keepFocusTag = f.tag }
        layoutMetrics(max(bounds.width, 200))
        doc.subviews.forEach { $0.removeFromSuperview() }
        let w = max(bounds.width - (scroll.verticalScroller?.isHidden == false ? 0 : 0), 200)
        var y: CGFloat = 20
        if editing { y = buildEdit(width: w) }
        else if let p = person { y = buildDisplay(p, width: w) }
        else if !placeholder.isEmpty {
            let l = NSTextField(labelWithString: placeholder); l.font = Fonts.regular(12); l.textColor = Pal.labelGrey; l.alignment = .center
            l.frame = NSRect(x: 10, y: bounds.height / 2 - 30, width: w - 20, height: 20); doc.addSubview(l)
        }
        doc.frame = NSRect(x: 0, y: 0, width: w, height: max(y + 20, bounds.height))
        if keepFocusTag != 0, let v = doc.viewWithTag(keepFocusTag) as? NSTextField {
            window?.makeFirstResponder(v); (window?.fieldEditor(false, for: v) as? NSTextView)?.setSelectedRange(NSRange(location: v.stringValue.count, length: 0))
        }
        if let f = firstFieldToFocus { window?.makeFirstResponder(f); firstFieldToFocus = nil }
    }

    private func highlighted(_ s: String, _ attrs: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let m = NSMutableAttributedString(string: s, attributes: attrs)
        if !highlight.isEmpty {
            for word in highlight.split(separator: " ") {
                var from = s.startIndex
                while let r = s.range(of: String(word), options: [.caseInsensitive, .diacriticInsensitive], range: from..<s.endIndex) {
                    m.addAttribute(.backgroundColor, value: NSColor.sg(0.78, 1), range: NSRange(r, in: s)); from = r.upperBound
                }
            }
        }
        return m
    }
    private func lined(_ s: NSAttributedString) -> NSAttributedString {
        let m = NSMutableAttributedString(attributedString: s)
        let p = NSMutableParagraphStyle(); p.minimumLineHeight = CardView.lineH; p.maximumLineHeight = CardView.lineH
        m.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: m.length)); return m
    }
    private func height(of s: NSAttributedString, width: CGFloat) -> CGFloat {
        ceil(s.boundingRect(with: NSSize(width: width, height: 10000), options: [.usesLineFragmentOrigin]).height)
    }

    private func valueLabel(_ s: NSAttributedString, y: CGFloat, width: CGFloat) -> (NSTextField, CGFloat) {
        let s = lined(s); let h = height(of: s, width: width - 4)
        let t = NSTextField(wrappingLabelWithString: ""); t.attributedStringValue = s
        t.isSelectable = true; t.allowsEditingTextAttributes = false; t.drawsBackground = false
        t.frame = NSRect(x: valueX, y: y, width: width, height: h); doc.addSubview(t)
        return (t, h)
    }

    private func buildDisplay(_ p: Person, width w: CGFloat) -> CGFloat {
        let vw = w - valueX - (compact ? 40 : 37)
        let photo = PhotoView(frame: NSRect(x: photoX, y: photoY, width: photoSize, height: photoSize))
        photo.image = p.photo.flatMap { NSImage(data: $0) }
        photo.setAccessibilityElement(false); doc.addSubview(photo)
        var y: CGFloat = photoY
        let name = highlighted(p.fullName, [.font: Fonts.bold(compact ? 13 : 14)])
        var (_, h) = valueLabel(name, y: y - 1, width: vw); y += h + 1
        var subs: [String] = []
        if !p.isCompany && !p.org.isEmpty { subs.append(p.org) }
        let jd = [p.job, p.dept].filter { !$0.isEmpty }.joined(separator: ", ")
        if !jd.isEmpty { subs.append(jd) }
        if !p.nickname.isEmpty && !p.isCompany && p.fullName != p.nickname { subs.append("„\(p.nickname)“") }
        for s in subs {
            (_, h) = valueLabel(highlighted(s, [.font: Fonts.regular(11), .foregroundColor: Pal.labelGrey]), y: y, width: vw); y += h
        }
        y = max(y, photoY + photoSize) + 15.5

        func row(_ label: String, _ value: NSAttributedString, menu: (() -> NSMenu?)?, link: (() -> Void)? = nil) {
            let fl = FieldLabel(frame: NSRect(x: areaX, y: y + 1, width: CardView.labelW, height: 15)); fl.text = label; fl.menuProvider = menu; doc.addSubview(fl)
            if let link = link {
                let t = LinkLabel(wrappingLabelWithString: ""); t.drawsBackground = false; let value = lined(value); t.attributedStringValue = value
                let hh = height(of: value, width: vw - 4); t.frame = NSRect(x: valueX, y: y, width: vw, height: hh); t.onClick = link; doc.addSubview(t); y += hh + 9
            } else { let (_, hh) = valueLabel(value, y: y, width: vw); y += hh + 10.5 }
        }
        let val: (String) -> NSAttributedString = { NSAttributedString(string: $0, attributes: [.font: Fonts.regular(11)]) }

        for ph in p.phones {
            row(Labels.text(ph.label), val(ph.value), menu: { [weak self] in self?.phoneMenu(ph.value) })
        }
        for m in p.emails {
            row(Labels.text(m.label), NSAttributedString(string: m.value, attributes: [.font: Fonts.regular(11), .foregroundColor: Pal.link]), menu: { [weak self] in self?.mailMenu(m.value) },
                link: { [weak self] in self?.open("mailto:\(m.value)") })
        }
        for u in p.urls {
            row(Labels.text(u.label), NSAttributedString(string: u.value, attributes: [.font: Fonts.regular(11), .foregroundColor: Pal.link, .underlineStyle: NSUnderlineStyle.single.rawValue]), menu: { [weak self] in self?.urlMenu(u.value) },
                link: { [weak self] in self?.open(u.value.contains("://") ? u.value : "http://" + u.value) })
        }
        for r in p.relations where !r.value.isEmpty { row(Labels.text(r.label), val(r.value), menu: { [weak self] in self?.copyMenu(r.value) }) }
        for im in p.ims where !im.username.isEmpty {
            let t = NSMutableAttributedString(string: im.username, attributes: [.font: Fonts.regular(11)])
            t.append(NSAttributedString(string: "  " + im.service, attributes: [.font: Fonts.regular(11), .foregroundColor: Pal.labelGrey]))
            row(Labels.text(im.label), t, menu: { [weak self] in self?.copyMenu(im.username) })
        }
        for c in p.chats where !c.value.isEmpty { row(c.label.lowercased(), val(c.value), menu: { [weak self] in self?.copyMenu(c.value) }) }
        for a in p.addrs {
            let txt = Self.formatAddress(a)
            row(Labels.text(a.label), val(txt), menu: { [weak self] in self?.addressMenu(txt) })
        }
        if let b = p.birthday, let d = Self.birthdayString(b) { row(L("Geburtstag", "birthday"), val(d), menu: nil) }
        // separator + note
        y -= 3; let line = DottedLine(frame: NSRect(x: sepX, y: y, width: w - sepX - rightMargin, height: 1)); doc.addSubview(line); y += 12
        let note = Store.shared.notes[p.id] ?? ""
        let fl = FieldLabel(frame: NSRect(x: areaX, y: y + 1, width: CardView.labelW, height: 15)); fl.text = L("Notiz", "note"); doc.addSubview(fl)
        fl.toolTip = L("Notizen werden lokal in RetroContacts gespeichert (kein Zugriff auf Systemnotizen).", "Notes are stored locally in RetroContacts (system notes are not accessed).")
        if !note.isEmpty { let (_, hh) = valueLabel(val(note), y: y, width: vw); y += hh } else { y += 16 }
        return y
    }

    static func formatAddress(_ a: PostalAddr) -> String {
        let pa = CNMutablePostalAddress(); pa.street = a.street; pa.city = a.city; pa.state = a.state; pa.postalCode = a.zip; pa.country = a.country
        let s = CNPostalAddressFormatter.string(from: pa, style: .mailingAddress)
        return s
    }
    static func birthdayString(_ c: DateComponents) -> String? {
        guard let m = c.month, let d = c.day else { return nil }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        var comps = c; comps.calendar = cal; comps.timeZone = cal.timeZone; comps.hour = 12
        let f = DateFormatter(); f.timeZone = cal.timeZone; f.locale = .current
        if c.year != nil, let date = cal.date(from: comps), c.year != 1604 { f.dateStyle = .long; f.timeStyle = .none; return f.string(from: date) }
        f.setLocalizedDateFormatFromTemplate("dMMMM")
        comps.year = 2000   // leap year so 29 Feb survives
        return cal.date(from: comps).map { f.string(from: $0) } ?? "\(d).\(m)."
    }

    // MARK: field actions (always from an explicit click)

    private func item(_ title: String, _ block: @escaping () -> Void) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: #selector(runBlock(_:)), keyEquivalent: ""); i.target = self; i.representedObject = block; return i
    }
    @objc private func runBlock(_ i: NSMenuItem) { (i.representedObject as? () -> Void)?() }
    private func copy(_ s: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string) }
    private func open(_ s: String) {
        guard let e = s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.union(.urlPathAllowed).union(CharacterSet(charactersIn: "%#:/?&=@+,;")).union(.alphanumerics)), let u = URL(string: e) else { return }
        NSWorkspace.shared.open(u)
    }
    private func copyMenu(_ s: String) -> NSMenu { let m = NSMenu(); m.addItem(item(L("Kopieren", "Copy")) { [weak self] in self?.copy(s) }); return m }
    private func phoneMenu(_ s: String) -> NSMenu {
        let digits = s.filter { "+0123456789".contains($0) }
        let m = copyMenu(s)
        m.addItem(item(L("Große Schrift", "Large Type")) { largeType(s) })
        m.addItem(.separator())
        m.addItem(item("FaceTime") { [weak self] in self?.open("facetime:\(digits)") })
        m.addItem(item(L("Anrufen", "Call")) { [weak self] in self?.open("tel:\(digits)") })
        m.addItem(item(L("Nachricht senden", "Send Message")) { [weak self] in self?.open("sms:\(digits)") })
        return m
    }
    private func mailMenu(_ s: String) -> NSMenu {
        let m = NSMenu(); m.addItem(item(L("E-Mail senden", "Send Email")) { [weak self] in self?.open("mailto:\(s)") }); m.addItem(item(L("Kopieren", "Copy")) { [weak self] in self?.copy(s) }); return m
    }
    private func urlMenu(_ s: String) -> NSMenu {
        let m = NSMenu(); m.addItem(item(L("URL öffnen", "Open URL")) { [weak self] in self?.open(s.contains("://") ? s : "http://" + s) }); m.addItem(item(L("Kopieren", "Copy")) { [weak self] in self?.copy(s) }); return m
    }
    private func addressMenu(_ s: String) -> NSMenu {
        let m = NSMenu()
        m.addItem(item(L("In Karten anzeigen", "Show in Maps")) { [weak self] in self?.open("http://maps.apple.com/?address=" + (s.replacingOccurrences(of: "\n", with: ", ").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")) })
        m.addItem(item(L("Kopieren", "Copy")) { [weak self] in self?.copy(s) }); return m
    }

    // MARK: edit mode (flat, borderless fields with grey placeholders; one blank row per group, like the original)

    var showNick = false, showJob = false
    func beginEdit(_ p: Person, note: String) {
        draft = p; draftNote = note; editing = true
        showNick = !p.nickname.isEmpty; showJob = !(p.job.isEmpty && p.dept.isEmpty)
        rebuild()
    }
    func endEdit() { editing = false; rebuild() }

    private func ph(_ s: String, _ f: NSFont) -> NSAttributedString { NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: NSColor.sg(0.68, 1)]) }
    @discardableResult
    private func field(_ text: String, ph p: String, tag: Int, font: NSFont = Fonts.regular(13), color: NSColor = .black, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat = 19, set: @escaping (String) -> Void) -> EditField {
        let f = EditField(frame: NSRect(x: x, y: y, width: w, height: h))
        f.stringValue = text; f.font = font; f.textColor = color; f.tag = tag
        f.placeholderAttributedString = ph(p, font)
        f.isBezeled = false; f.isBordered = false; f.drawsBackground = false; f.focusRingType = .default
        f.delegate = self; f.onText = set; f.cell?.usesSingleLineMode = true; f.cell?.isScrollable = true
        f.setAccessibilityLabel(p); doc.addSubview(f); return f
    }
    func controlTextDidChange(_ n: Notification) { if let f = n.object as? EditField { f.onText?(f.stringValue) } }
    func textDidChange(_ n: Notification) { if let t = n.object as? NSTextView { draftNote = t.string } }

    private func scheduleRebuild() { DispatchQueue.main.async { [weak self] in self?.rebuildKeepingScroll() } }
    func rebuildKeepingScroll() {
        let o = scroll.contentView.bounds.origin; rebuild(); scroll.contentView.scroll(to: o); scroll.reflectScrolledClipView(scroll.contentView)
    }
    private func labelPopup(_ options: [String], current: String, y: CGFloat, set: @escaping (String) -> Void) {
        let b = LabelMenu(frame: NSRect(x: labelRight - 117, y: y, width: 120, height: 19))
        b.configure(options: options, current: current, text: { Labels.text($0) }, grey: true, onChange: { [weak self] v in set(v); self?.rebuildKeepingScroll() })
        doc.addSubview(b)
    }
    private func minus(y: CGFloat, _ act: @escaping () -> Void) {
        let m = RoundIconButton(.minus); m.frame.origin = NSPoint(x: max(6, labelRight - 127), y: y + 3); m.target = self; m.action = #selector(removeRow(_:))
        objc_setAssociatedObject(m, "rm", act, .OBJC_ASSOCIATION_RETAIN); doc.addSubview(m)
    }

    private func buildEdit(width w: CGFloat) -> CGFloat {
        let vw = w - valueX - (compact ? 40 : 37)
        let photo = PhotoView(frame: NSRect(x: photoX, y: photoY, width: photoSize, height: photoSize))
        photo.image = draft.photo.flatMap { NSImage(data: $0) }; photo.editable = true
        photo.onChange = { [weak self] d in self?.draft.photo = d }
        doc.addSubview(photo)
        let nameFont = Fonts.bold(compact ? 13 : 14)
        var y = photoY
        if draft.asCompany {
            field(draft.org, ph: L("Firma", "Company"), tag: 13, font: nameFont, x: valueX, y: y - 1.5, w: vw, h: 20) { [weak self] in self?.draft.org = $0 }
        } else {
            // first and last name sit on one line, as one name
            let fw = ceil((draft.given as NSString).size(withAttributes: [.font: nameFont]).width)
            let firstW = min(vw - 60, max(60, fw + 10))
            let first = field(draft.given, ph: L("Vorname", "First"), tag: 11, font: nameFont, x: valueX, y: y - 1.5, w: firstW, h: 20) { [weak self] in self?.draft.given = $0 }
            field(draft.family, ph: L("Nachname", "Last"), tag: 12, font: nameFont, x: valueX + firstW, y: y - 1.5, w: vw - firstW, h: 20) { [weak self] in self?.draft.family = $0 }
            if draft.isNew && draft.given.isEmpty && draft.family.isEmpty && draft.org.isEmpty && window?.firstResponder is NSTextView == false { firstFieldToFocus = first }
            field(draft.org, ph: L("Firma", "Company"), tag: 13, font: Fonts.regular(12), color: Pal.labelGrey, x: valueX, y: y + 14.4, w: vw, h: 18) { [weak self] in self?.draft.org = $0 }
        }
        let cb = NSButton(checkboxWithTitle: L("Firma", "Company"), target: self, action: #selector(toggleCompany(_:)))
        cb.font = Fonts.regular(10); cb.controlSize = .mini; cb.state = draft.asCompany ? .on : .off
        cb.frame = NSRect(x: valueX - 2, y: photoY + 33, width: 90, height: 16); doc.addSubview(cb)
        y = photoY + 63

        if showNick {
            let fl = FieldLabel(frame: NSRect(x: labelRight - 90, y: y + 1, width: 90, height: 16)); fl.text = L("Spitzname", "nickname"); doc.addSubview(fl)
            field(draft.nickname, ph: L("Spitzname", "Nickname"), tag: 14, x: valueX, y: y, w: vw) { [weak self] in self?.draft.nickname = $0 }; y += 28
        }
        if showJob {
            let fl = FieldLabel(frame: NSRect(x: labelRight - 90, y: y + 1, width: 90, height: 16)); fl.text = L("Position", "job title"); doc.addSubview(fl)
            field(draft.job, ph: L("Position", "Job Title"), tag: 15, x: valueX, y: y, w: vw / 2 - 3) { [weak self] in self?.draft.job = $0 }
            field(draft.dept, ph: L("Abteilung", "Department"), tag: 16, x: valueX + vw / 2 + 3, y: y, w: vw / 2 - 3) { [weak self] in self?.draft.dept = $0 }; y += 28
        }

        func list(_ kp: WritableKeyPath<Person, [LabeledText]>, base: Int, labels: [String], placeholder: String, defaultLabel: String) {
            if draft[keyPath: kp].last.map({ !$0.value.isEmpty }) ?? true {
                // next unused standard label (work, then home, then other) like the original
                let used = Set(draft[keyPath: kp].map { $0.label })
                let next = draft[keyPath: kp].isEmpty ? defaultLabel : (labels.first { !used.contains($0) } ?? defaultLabel)
                draft[keyPath: kp].append(LabeledText(label: next, value: ""))
            }
            let n = draft[keyPath: kp].count
            for i in 0..<n {
                let it = draft[keyPath: kp][i]
                if !it.value.isEmpty { minus(y: y) { [weak self] in self?.draft[keyPath: kp].remove(at: i); self?.rebuildKeepingScroll() } }
                labelPopup(labels, current: it.label, y: y) { [weak self] v in self?.draft[keyPath: kp][i].label = v }
                field(it.value, ph: placeholder, tag: base + i, x: valueX, y: y, w: vw) { [weak self] v in
                    guard let s = self else { return }
                    let wasEmpty = s.draft[keyPath: kp][i].value.isEmpty
                    s.draft[keyPath: kp][i].value = v
                    if wasEmpty && !v.isEmpty && i == s.draft[keyPath: kp].count - 1 { s.scheduleRebuild() }
                }
                y += 18
            }
            y += 10
        }
        list(\.phones, base: 1000, labels: Labels.phone, placeholder: L("Telefon", "Phone"), defaultLabel: CNLabelPhoneNumberMobile)
        list(\.emails, base: 2000, labels: Labels.mail, placeholder: L("E-Mail", "Email"), defaultLabel: CNLabelWork)
        list(\.urls, base: 3000, labels: Labels.url, placeholder: "URL", defaultLabel: CNLabelURLAddressHomePage)
        list(\.relations, base: 3500, labels: Labels.relation, placeholder: L("Verwandte Person", "Related Name"), defaultLabel: CNLabelContactRelationMother)

        // instant messaging: label, user name, service
        if draft.ims.last.map({ !$0.username.isEmpty }) ?? true { draft.ims.append(IMAddr(label: CNLabelHome, service: CNInstantMessageServiceAIM, username: "")) }
        for i in 0..<draft.ims.count {
            let im = draft.ims[i]
            if !im.username.isEmpty { minus(y: y) { [weak self] in self?.draft.ims.remove(at: i); self?.rebuildKeepingScroll() } }
            labelPopup(Labels.mail, current: im.label, y: y) { [weak self] v in self?.draft.ims[i].label = v }
            field(im.username, ph: L("Benutzername", "User Name"), tag: 3700 + i, x: valueX, y: y, w: vw - 70) { [weak self] v in
                guard let s = self else { return }
                let was = s.draft.ims[i].username.isEmpty; s.draft.ims[i].username = v
                if was && !v.isEmpty && i == s.draft.ims.count - 1 { s.scheduleRebuild() }
            }
            let sv = LabelMenu(frame: NSRect(x: valueX + vw - 66, y: y, width: 66, height: 19))
            sv.configure(options: Labels.imServices, current: im.service, text: { $0 }, grey: false, leftAligned: true, onChange: { [weak self] v in self?.draft.ims[i].service = v; self?.rebuildKeepingScroll() })
            doc.addSubview(sv)
            y += 18
        }
        y += 10

        if draft.addrs.last.map({ !$0.isEmpty }) ?? true { draft.addrs.append(PostalAddr(label: CNLabelWork)) }
        for i in 0..<draft.addrs.count {
            let a = draft.addrs[i], t = 4000 + i * 10
            if !a.isEmpty { minus(y: y) { [weak self] in self?.draft.addrs.remove(at: i); self?.rebuildKeepingScroll() } }
            labelPopup(Labels.addr, current: a.label, y: y) { [weak self] v in self?.draft.addrs[i].label = v }
            func upd(_ s: CardView, _ f: (inout PostalAddr) -> Void) {
                let was = s.draft.addrs[i].isEmpty; f(&s.draft.addrs[i])
                if was && !s.draft.addrs[i].isEmpty && i == s.draft.addrs.count - 1 { s.scheduleRebuild() }
            }
            field(a.street, ph: L("Straße", "Street"), tag: t, x: valueX, y: y, w: vw) { [weak self] v in if let s = self { upd(s) { $0.street = v } } }; y += 18
            let cw = vw * 0.5, sw = vw * 0.25
            field(a.city, ph: L("Ort", "City"), tag: t + 1, x: valueX, y: y, w: cw - 4) { [weak self] v in if let s = self { upd(s) { $0.city = v } } }
            field(a.state, ph: L("Region", "State"), tag: t + 2, x: valueX + cw, y: y, w: sw - 4) { [weak self] v in if let s = self { upd(s) { $0.state = v } } }
            field(a.zip, ph: L("PLZ", "ZIP"), tag: t + 3, x: valueX + cw + sw, y: y, w: sw) { [weak self] v in if let s = self { upd(s) { $0.zip = v } } }; y += 18
            field(a.country, ph: L("Land", "Country"), tag: t + 4, x: valueX, y: y, w: vw) { [weak self] v in if let s = self { upd(s) { $0.country = v } } }; y += 28
        }

        if let b = draft.birthday {
            minus(y: y) { [weak self] in self?.draft.birthday = nil; self?.rebuildKeepingScroll() }
            let fl = FieldLabel(frame: NSRect(x: labelRight - 90, y: y + 1, width: 90, height: 16)); fl.text = L("Geburtstag", "birthday"); doc.addSubview(fl)
            field(b.day.map(String.init) ?? "", ph: L("Tag", "Day"), tag: 5001, x: valueX, y: y, w: 34) { [weak self] in self?.draft.birthday?.day = Int($0) }
            let mp = NSPopUpButton(frame: NSRect(x: valueX + 38, y: y - 2, width: 112, height: 22), pullsDown: false)
            mp.isBordered = false; mp.font = Fonts.regular(13); mp.addItems(withTitles: Calendar.current.monthSymbols); mp.selectItem(at: max(0, (b.month ?? 1) - 1))
            mp.target = self; mp.action = #selector(monthChanged(_:)); doc.addSubview(mp)
            let yr = (b.year == 1604 || b.year == nil) ? "" : String(b.year!)
            field(yr, ph: L("Jahr", "Year"), tag: 5003, x: valueX + 154, y: y, w: 50) { [weak self] in self?.draft.birthday?.year = Int($0) }
            y += 28
        }

        // separator, note, "add field"
        let line = DottedLine(frame: NSRect(x: sepX, y: y, width: w - sepX - rightMargin, height: 1)); doc.addSubview(line); y += 12
        let fl = FieldLabel(frame: NSRect(x: labelRight - 90, y: y + 1, width: 90, height: 16)); fl.text = L("Notiz", "note"); doc.addSubview(fl)
        let ns = NSScrollView(frame: NSRect(x: valueX, y: y, width: vw, height: 64)); ns.borderType = .lineBorder; ns.hasVerticalScroller = true; ns.scrollerStyle = .legacy
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: vw - 14, height: 64)); tv.font = Fonts.regular(12); tv.string = draftNote; tv.delegate = self
        tv.isRichText = false; tv.isVerticallyResizable = true; tv.autoresizingMask = [.width]; tv.textContainerInset = NSSize(width: 2, height: 3)
        tv.setAccessibilityLabel(L("Notiz", "Note")); ns.documentView = tv; doc.addSubview(ns)
        y += 72
        let add = NSPopUpButton(frame: NSRect(x: valueX - 4, y: y, width: 150, height: 20), pullsDown: true)
        add.isBordered = false; add.font = Fonts.regular(11)
        add.addItem(withTitle: L("Feld hinzufügen", "add field"))
        if !showNick { add.addItem(withTitle: L("Spitzname", "Nickname")) }
        if !showJob { add.addItem(withTitle: L("Position / Abteilung", "Job Title / Department")) }
        if draft.birthday == nil { add.addItem(withTitle: L("Geburtstag", "Birthday")) }
        add.target = self; add.action = #selector(addFieldChosen(_:)); add.isHidden = add.numberOfItems < 2; doc.addSubview(add)
        return y + 24
    }

    @objc func addFieldChosen(_ p: NSPopUpButton) {
        guard let t = p.titleOfSelectedItem else { return }
        if t == L("Spitzname", "Nickname") { showNick = true }
        else if t == L("Position / Abteilung", "Job Title / Department") { showJob = true }
        else if t == L("Geburtstag", "Birthday") { draft.birthday = DateComponents(month: 1, day: 1) }
        rebuildKeepingScroll()
    }
    @objc func toggleCompany(_ b: NSButton) {
        draft.asCompany = b.state == .on
        if draft.asCompany { if draft.org.isEmpty { draft.org = [draft.given, draft.family].filter { !$0.isEmpty }.joined(separator: " ") }; draft.given = ""; draft.family = "" }
        rebuildKeepingScroll()
    }
    @objc func removeRow(_ s: NSControl) { (objc_getAssociatedObject(s, "rm") as? () -> Void)?() }
    @objc func monthChanged(_ p: NSPopUpButton) { draft.birthday?.month = p.indexOfSelectedItem + 1 }
}

/// Right-aligned grey label with tiny up/down arrows; click opens the choice menu (checked current value, "Custom…").
final class LabelMenu: NSView {
    private var options: [String] = [], current = "", text: (String) -> String = { $0 }
    private var onChange: ((String) -> Void)?
    private var grey = true, leftAligned = false
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    func configure(options: [String], current: String, text: @escaping (String) -> String, grey: Bool, leftAligned: Bool = false, onChange: @escaping (String) -> Void) {
        self.options = options; self.current = current; self.text = text; self.grey = grey; self.leftAligned = leftAligned; self.onChange = onChange
        setAccessibilityRole(.popUpButton); setAccessibilityLabel(text(current)); needsDisplay = true
    }
    override func draw(_ r: NSRect) {
        let col = grey ? Pal.labelGrey : NSColor.black
        let s = NSAttributedString(string: text(current), attributes: [.font: Fonts.regular(13), .foregroundColor: col])
        let sz = s.size()
        let ax = bounds.width - 4                       // arrows hug the right edge
        s.draw(at: NSPoint(x: leftAligned ? 0 : ax - 10 - sz.width, y: (bounds.height - sz.height) / 2))
        let ox = leftAligned ? min(sz.width + 6, bounds.width - 8) + 4 : ax - 2
        (grey ? NSColor.sg(0.62, 1) : NSColor.black).setFill()
        let up = NSBezierPath(); up.move(to: NSPoint(x: ox - 3, y: bounds.midY - 1.5)); up.line(to: NSPoint(x: ox + 3, y: bounds.midY - 1.5)); up.line(to: NSPoint(x: ox, y: bounds.midY - 4.8)); up.close(); up.fill()
        let dn = NSBezierPath(); dn.move(to: NSPoint(x: ox - 3, y: bounds.midY + 1.5)); dn.line(to: NSPoint(x: ox + 3, y: bounds.midY + 1.5)); dn.line(to: NSPoint(x: ox, y: bounds.midY + 4.8)); dn.close(); dn.fill()
    }
    override func mouseDown(with e: NSEvent) {
        let m = NSMenu()
        var opts = options; if !current.isEmpty && !opts.contains(current) { opts.append(current) }
        for (i, o) in opts.enumerated() {
            let it = NSMenuItem(title: text(o), action: #selector(pick(_:)), keyEquivalent: ""); it.target = self; it.tag = i; it.state = o == current ? .on : .off; m.addItem(it)
        }
        if !grey == false {
            m.addItem(.separator())
            let c = NSMenuItem(title: L("Eigene …", "Custom…"), action: #selector(custom), keyEquivalent: ""); c.target = self; m.addItem(c)
        }
        objc_setAssociatedObject(self, "opts", opts, .OBJC_ASSOCIATION_RETAIN)
        m.popUp(positioning: m.items.first { $0.state == .on }, at: NSPoint(x: leftAligned ? 0 : bounds.width - 70, y: 2), in: self)
    }
    @objc private func pick(_ i: NSMenuItem) { if let o = objc_getAssociatedObject(self, "opts") as? [String], i.tag < o.count { onChange?(o[i.tag]) } }
    @objc private func custom() {
        let a = NSAlert(); a.messageText = L("Eigene Bezeichnung", "Custom Label"); a.addButton(withTitle: "OK"); a.addButton(withTitle: L("Abbrechen", "Cancel"))
        let t = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 22)); a.accessoryView = t
        if a.runModal() == .alertFirstButtonReturn, !t.stringValue.isEmpty { onChange?(t.stringValue) }
    }
}
