import Cocoa
import UniformTypeIdentifiers

/// Bold group title with a chevron (two-pane mode); pops up the list of sources.
final class TitleMenuButton: NSControl {
    var title = "" { didSet { needsDisplay = true } }
    var menuProvider: (() -> NSMenu?)?
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func draw(_ r: NSRect) {
        let s = NSAttributedString(string: title, attributes: [.font: Fonts.bold(12), .foregroundColor: Pal.sideBlue])
        let sz = s.size(); let x = max(0, (bounds.width - sz.width - 12) / 2)
        s.draw(with: NSRect(x: x, y: (bounds.height - sz.height) / 2, width: min(sz.width, bounds.width - 14), height: sz.height), options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin])
        let cx = min(x + sz.width + 8, bounds.width - 5), cy = bounds.midY
        Pal.sideBlue.setFill()
        let up = NSBezierPath(); up.move(to: NSPoint(x: cx - 3, y: cy - 1)); up.line(to: NSPoint(x: cx + 3, y: cy - 1)); up.line(to: NSPoint(x: cx, y: cy - 4.5)); up.close(); up.fill()
        let dn = NSBezierPath(); dn.move(to: NSPoint(x: cx - 3, y: cy + 1)); dn.line(to: NSPoint(x: cx + 3, y: cy + 1)); dn.line(to: NSPoint(x: cx, y: cy + 4.5)); dn.close(); dn.fill()
    }
    override func mouseDown(with e: NSEvent) { menuProvider?()?.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + 2), in: self) }
}

final class MainController: NSObject, NSWindowDelegate {
    let window: BookWindow
    let book = BookView(frame: .zero)
    let sidebar = Sidebar(), list = ContactList(), card = CardView()
    let search = RetroSearchField()
    let plusButton = RetroButton(glyph: Glyph.plus)
    let segmented = RetroSegmented(glyphs: [Glyph.viewMode(0), Glyph.viewMode(1), Glyph.viewMode(2)])
    let editButton = RetroButton(title: L("Bearbeiten", "Edit"))
    let cancelButton = RetroButton(title: L("Abbrechen", "Cancel"))
    let shareButton = RetroButton(glyph: Glyph.share)
    let prevButton = RetroButton(glyph: Glyph.triangle(left: true))
    let nextButton = RetroButton(glyph: Glyph.triangle(left: false))
    let titleButton = TitleMenuButton()

    var store: Store { Store.shared }
    var mode: ViewMode
    var source: Source = .all
    var query = ""
    var visible: [Person] = []
    var selectedIDs: [String] = []
    var selectedID: String? { selectedIDs.first }
    var editing: Bool { card.editing }
    var shareTemp: URL?

    override init() {
        let m = ViewMode(rawValue: UserDefaults.standard.integer(forKey: "viewMode")) ?? .three
        mode = m
        let size = MainController.savedSize(m)
        window = BookWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.miniaturizable, .closable], backing: .buffered, defer: false)
        super.init()
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.title = L("Kontakte", "Contacts")
        window.setFrameAutosaveName("")
        window.autorecalculatesKeyViewLoop = true
        window.collectionBehavior = [.fullScreenNone]
        window.minSize = m.minSize; window.maxSize = m.maxSize
        window.contentView = book
        book.mode = m
        book.onLayout = { [weak self] in self?.layoutAll() }
        [sidebar, list, search, card, plusButton, segmented, editButton, cancelButton, shareButton, prevButton, nextButton, titleButton].forEach { book.addSubview($0) }
        // keep traffic lights above everything
        book.lights.forEach { book.addSubview($0) }
        wire()
        if let f = UserDefaults.standard.string(forKey: "frame.\(m.rawValue)") { window.setFrame(NSRectFromString(f), display: false) } else { window.center() }
        clampToScreen()
    }

    static func savedSize(_ m: ViewMode) -> NSSize {
        if let f = UserDefaults.standard.string(forKey: "frame.\(m.rawValue)") { let r = NSRectFromString(f); if r.width > 0 { return r.size } }
        return m.defaultSize
    }
    func clampToScreen() {
        guard let vis = NSScreen.main?.visibleFrame else { return }
        var f = window.frame
        f.size.width = min(f.width, vis.width); f.size.height = min(f.height, vis.height)
        if !vis.intersects(f) { f.origin = NSPoint(x: vis.midX - f.width / 2, y: vis.midY - f.height / 2) }
        window.setFrame(f, display: false)
    }

    // MARK: wiring

    func wire() {
        plusButton.target = self; plusButton.action = #selector(plusPressed)
        plusButton.popUpMenu = { [weak self] in self?.plusMenu() }
        plusButton.setAccessibilityLabel(L("Hinzufügen", "Add"))
        segmented.selected = mode.rawValue
        segmented.onSelect = { [weak self] i in self?.setMode(ViewMode(rawValue: i)!) }
        editButton.target = self; editButton.action = #selector(toggleEdit)
        cancelButton.target = self; cancelButton.action = #selector(cancelEdit)
        shareButton.setAccessibilityLabel(L("Teilen", "Share"))
        shareButton.popUpMenu = { [weak self] in self?.shareMenu() }
        prevButton.target = self; prevButton.action = #selector(previousCard); prevButton.setAccessibilityLabel(L("Vorherige Karte", "Previous Card"))
        nextButton.target = self; nextButton.action = #selector(nextCard); nextButton.setAccessibilityLabel(L("Nächste Karte", "Next Card"))
        titleButton.menuProvider = { [weak self] in self?.sourceMenu() }
        search.onChange = { [weak self] q in self?.searchChanged(q) }
        list.onSelect = { [weak self] ids in self?.listSelected(ids) }
        list.onDoubleClick = { [weak self] in if self?.editing == false { self?.toggleEdit() } }
        sidebar.onSelect = { [weak self] s in self?.sourceSelected(s) }
        sidebar.onMenu = { [weak self] it in self?.groupMenu(it) }
        sidebar.onDrop = { [weak self] g, ids in self?.store.add(ids, to: g); self?.reloadAll(); return true }
        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged), name: .storeChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(prefsChanged), name: .prefsChanged, object: nil)
    }

    @objc func storeChanged() { if !editing { reloadAll() } }     // D-06: never overwrite a draft in progress
    @objc func prefsChanged() { applyList(); }

    // MARK: layout

    func layoutAll() {
        let g = book.geo, st = BookGeo.edgeStripes
        let pt = g.pages.minY
        let bh: CGFloat = 21, bottomY = book.bounds.height - 37.5     // buttons 16.5 pt above the window edge (measured)
        let rp = g.rightPage
        let three = mode == .three, two = mode == .two, one = mode == .one
        sidebar.isHidden = !three; list.isHidden = one; titleButton.isHidden = !two
        prevButton.isHidden = !one || editing; nextButton.isHidden = !one || editing
        plusButton.isHidden = false; segmented.isHidden = false
        card.compact = one

        func w(_ b: RetroButton) -> CGFloat {
            if b.glyph != nil { return 36 }
            return max(38, ceil((b.title as NSString).size(withAttributes: [.font: Fonts.regular(11)]).width) + 20)
        }
        var searchFrame = NSRect.zero
        if let lp = g.leftPage, let f = g.fold {
            var listX = lp.minX + st + 10
            if three {
                sidebar.frame = NSRect(x: lp.minX + st, y: pt + 38, width: BookGeo.sidebarDivider - (lp.minX + st), height: bottomY - 10 - (pt + 38))
                listX = BookGeo.sidebarDivider + 17
            }
            let listR = f - 26.5
            searchFrame = NSRect(x: listX, y: pt + 38.5, width: listR - listX, height: 18)
            titleButton.frame = NSRect(x: lp.minX + 84, y: pt + 6, width: max(60, listR - (lp.minX + 84)), height: 18)
            list.frame = NSRect(x: listX, y: pt + 64.8, width: listR - listX, height: bottomY - 10 - (pt + 64.8))
            plusButton.frame = NSRect(x: listX, y: bottomY, width: 27, height: bh)
            segmented.frame = NSRect(x: listR - 80, y: bottomY, width: 80, height: bh)
        }
        let right = rp.maxX - st
        if one {
            // card-only window (measured on the original): lights and search share the top row, paging sits bottom right
            let W = book.bounds.width
            searchFrame = NSRect(x: 87, y: 13, width: W - 28 - 87, height: 18)
            card.frame = NSRect(x: 0, y: 34, width: W, height: bottomY - 6 - 34)
            var x: CGFloat = 34
            plusButton.frame = NSRect(x: x, y: bottomY, width: 27, height: bh); x += 27 + 5
            segmented.frame = NSRect(x: x, y: bottomY, width: 80, height: bh); x += 80 + 6
            let ew = w(editButton); editButton.frame = NSRect(x: x, y: bottomY, width: ew, height: bh); x += ew + 5
            if editing { let cw = w(cancelButton); cancelButton.frame = NSRect(x: x, y: bottomY, width: cw, height: bh); x += cw + 5 }
            shareButton.frame = NSRect(x: x, y: bottomY, width: 36, height: bh)
            prevButton.frame = NSRect(x: W - 22 - 50, y: bottomY, width: 25, height: bh); nextButton.frame = NSRect(x: W - 22 - 25, y: bottomY, width: 25, height: bh)
            prevButton.segmentPosition = (true, false); nextButton.segmentPosition = (false, true)
        } else {
            card.frame = NSRect(x: rp.minX, y: pt, width: right - rp.minX, height: bottomY - 6 - pt)
            let ex = rp.minX + 29
            let ew = w(editButton); editButton.frame = NSRect(x: ex, y: bottomY, width: ew, height: bh)
            let cw = w(cancelButton); cancelButton.frame = NSRect(x: ex + ew + 5, y: bottomY, width: cw, height: bh)
            shareButton.frame = NSRect(x: editing ? cancelButton.frame.maxX + 5 : ex + ew + 5, y: bottomY, width: 36, height: bh)
        }
        search.frame = searchFrame
        cancelButton.isHidden = !editing
    }

    // MARK: state

    func setMode(_ m: ViewMode) {
        guard m != mode else { return }
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: "frame.\(mode.rawValue)")
        mode = m; UserDefaults.standard.set(m.rawValue, forKey: "viewMode")
        let size = MainController.savedSize(m)
        var f = window.frame
        f.origin.y = f.maxY - size.height; f.size = size
        window.minSize = m.minSize; window.maxSize = m.maxSize
        window.setFrame(f, display: true)
        clampToScreen()
        book.mode = m; segmented.selected = m.rawValue
        layoutAll(); book.needsLayout = true; window.invalidateShadow()
        window.makeFirstResponder(m == .one ? card : list.table)
        refreshUI()
    }
    func windowDidResize(_ n: Notification) { UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: "frame.\(mode.rawValue)"); window.invalidateShadow() }
    func windowDidMove(_ n: Notification) { UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: "frame.\(mode.rawValue)") }
    func windowDidBecomeKey(_ n: Notification) { list.table.refreshEmphasis(); sidebar.table.refreshEmphasis() }
    func windowDidResignKey(_ n: Notification) { list.table.refreshEmphasis(); sidebar.table.refreshEmphasis() }

    func start() {
        window.makeKeyAndOrderFront(nil)
        store.requestAccess { [weak self] in
            guard let self = self else { return }
            if self.store.access == .denied { self.showDenied() }
            self.reloadAll()
            if self.selectedID == nil { self.list.select(id: self.visible.first?.id); self.listSelected(self.list.selectedIDs) }
        }
    }

    func showDenied() {
        list.emptyText = L("Kein Zugriff auf Kontakte.\nErlauben Sie RetroContacts den Zugriff in den Systemeinstellungen.", "No access to Contacts.\nAllow RetroContacts in System Settings.")
        card.placeholder = L("Kontaktzugriff nicht erlaubt", "Contacts access not allowed")
        let a = NSAlert(); a.messageText = L("RetroContacts hat keinen Zugriff auf Ihre Kontakte", "RetroContacts can't access your contacts")
        a.informativeText = L("Öffnen Sie Systemeinstellungen › Datenschutz & Sicherheit › Kontakte und aktivieren Sie RetroContacts.", "Open System Settings › Privacy & Security › Contacts and enable RetroContacts.")
        a.addButton(withTitle: L("Systemeinstellungen öffnen", "Open System Settings")); a.addButton(withTitle: L("Später", "Later"))
        if a.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts")!) }
    }

    func computeVisible() {
        var ppl = store.people
        switch source {
        case .all: break
        case .container(let id): ppl = ppl.filter { $0.containerID == id }
        case .group(let id): let m = store.groups.first { $0.id == id }?.members ?? []; ppl = ppl.filter { m.contains($0.id) }
        case .smart(let id): if let g = store.smartGroups.first(where: { $0.id == id }) { ppl = ppl.filter { g.matches($0) } } else { ppl = [] }
        }
        if !query.isEmpty { ppl = ppl.filter { $0.matches(query) } }
        visible = ppl
    }

    func reloadAll() {
        if case .group(let id) = source, !store.groups.contains(where: { $0.id == id }) { source = .all }
        if case .smart(let id) = source, !store.smartGroups.contains(where: { $0.id == id }) { source = .all }
        sidebar.reload(selecting: source)
        applyList()
    }

    func applyList() {
        computeVisible()
        if store.access == .granted {
            if store.people.isEmpty { list.emptyText = L("Keine Kontakte", "No Contacts") }
            else if !query.isEmpty { list.emptyText = L("Keine Treffer", "No Matches") }
            else { list.emptyText = L("Keine Karten in dieser Gruppe", "No cards in this group") }
        }
        let keep = selectedIDs.filter { id in visible.contains { $0.id == id } }
        list.setPeople(visible, keepSelection: keep)
        selectedIDs = list.selectedIDs
        if selectedIDs.isEmpty && !editing, let f = list.firstPersonID() { list.select(id: f); selectedIDs = [f] }
        refreshUI()
    }

    func refreshUI() {
        titleButton.title = sourceTitle()
        if !editing {
            if selectedIDs.count > 1 { card.person = nil; card.placeholder = L("\(selectedIDs.count) Karten ausgewählt", "\(selectedIDs.count) cards selected") }
            else if let id = selectedID, let p = store.people.first(where: { $0.id == id }) { card.placeholder = ""; card.person = p }
            else { card.person = nil; if store.access == .granted { card.placeholder = L("Keine Karte ausgewählt", "No Card Selected") } }
        }
        editButton.title = editing ? L("Fertig", "Done") : L("Bearbeiten", "Edit")
        editButton.titleColor = editing ? NSColor(srgbRed: 0.05, green: 0.38, blue: 0.85, alpha: 1) : nil
        search.count = query.isEmpty ? nil : visible.count
        card.highlight = query
        editButton.isEnabled = editing || selectedIDs.count == 1
        shareButton.isEnabled = !editing && !selectedIDs.isEmpty
        plusButton.isEnabled = !editing && store.access != .denied || store.demo
        prevButton.isEnabled = !editing && list.canMove(-1); nextButton.isEnabled = !editing && list.canMove(1)
        window.title = sourceTitle()
        layoutAll(); book.needsLayout = true
    }

    func sourceTitle() -> String {
        switch source {
        case .all: return L("Alle Kontakte", "All Contacts")
        case .container(let id): return L("Alle ", "All ") + (store.containers.first { $0.id == id }?.name ?? "")
        case .group(let id): return store.groups.first { $0.id == id }?.name ?? ""
        case .smart(let id): return store.smartGroups.first { $0.id == id }?.name ?? ""
        }
    }

    // MARK: events

    func searchChanged(_ q: String) {
        query = q; applyList()
        if !editing, selectedIDs.isEmpty { card.person = nil }
    }

    func sourceSelected(_ s: Source) {
        guard !editing || confirmLeave() else { sidebar.select(source); return }
        source = s; applyList()
    }

    func listSelected(_ ids: [String]) {
        if editing {
            if ids == selectedIDs { return }
            guard confirmLeave() else { list.select(id: selectedID); return }
        }
        selectedIDs = ids; refreshUI()
    }

    @objc func previousCard() { list.selectAdjacent(-1) }
    @objc func nextCard() { list.selectAdjacent(1) }

    // MARK: editing

    /// K-03: Speichern / Verwerfen / Weiterbearbeiten
    func confirmLeave() -> Bool {
        let a = NSAlert(); a.messageText = L("Möchten Sie die Änderungen an dieser Karte sichern?", "Do you want to save the changes to this card?")
        a.informativeText = L("Ihre Änderungen gehen verloren, wenn Sie sie nicht sichern.", "Your changes will be lost if you don't save them.")
        a.addButton(withTitle: L("Sichern", "Save")); a.addButton(withTitle: L("Weiterbearbeiten", "Keep Editing")); a.addButton(withTitle: L("Verwerfen", "Discard"))
        switch a.runModal() {
        case .alertFirstButtonReturn: return saveDraft()
        case .alertThirdButtonReturn: card.endEdit(); return true
        default: return false
        }
    }

    @objc func toggleEdit() {
        if editing { _ = saveDraft(); return }
        guard selectedIDs.count == 1, let p = store.people.first(where: { $0.id == selectedID }) else { return }
        card.beginEdit(p, note: store.notes[p.id] ?? ""); refreshUI()
    }
    @objc func cancelEdit() {
        card.endEdit(); selectedIDs = list.selectedIDs; refreshUI()
    }

    @discardableResult func saveDraft() -> Bool {
        var d = card.draft
        d.given = d.given.trimmingCharacters(in: .whitespaces); d.family = d.family.trimmingCharacters(in: .whitespaces)
        guard let id = store.save(d) else {
            let a = NSAlert(); a.alertStyle = .warning; a.messageText = L("Die Karte konnte nicht gesichert werden.", "The card could not be saved.")
            a.informativeText = (store.lastError ?? "") + "\n" + L("Ihre Eingaben bleiben erhalten.", "Your input has been kept.")
            a.runModal(); return false
        }
        store.setNote(card.draftNote, for: id)
        card.endEdit()
        store.reload(); selectedIDs = [id]
        computeVisible()
        if !visible.contains(where: { $0.id == id }) { source = .all; sidebar.select(.all); query = ""; search.text = "" }
        applyList(); list.select(id: id); selectedIDs = [id]; refreshUI()
        return true
    }

    @objc func newCard() {
        if editing && !confirmLeave() { return }
        var p = Person(id: UUID().uuidString); p.isNew = true
        switch source {
        case .container(let id): p.containerID = id
        case .group(let id): p.containerID = store.groups.first { $0.id == id }?.containerID ?? ""
        default: break
        }
        if p.containerID.isEmpty { p.containerID = store.demo ? "icloud" : store.cn.defaultContainerIdentifier() }
        p.phones = [LabeledText(label: "_$!<Work>!$_", value: "")]; p.emails = [LabeledText(label: "_$!<Work>!$_", value: "")]
        list.table.deselectAll(nil); selectedIDs = []
        card.beginEdit(p, note: ""); refreshUI()
    }

    @objc func deleteCard() {
        let ps = store.people.filter { selectedIDs.contains($0.id) }
        guard !ps.isEmpty, !editing else { return }
        let a = NSAlert(); a.alertStyle = .warning
        let names = ps.prefix(3).map { $0.fullName }.joined(separator: ", ")
        a.messageText = ps.count == 1 ? L("Möchten Sie „\(names)“ löschen?", "Do you want to delete “\(names)”?") : L("Möchten Sie \(ps.count) Karten löschen?", "Do you want to delete \(ps.count) cards?")
        let srcs = Set(ps.compactMap { p in store.containers.first { $0.id == p.containerID }?.name }).joined(separator: ", ")
        a.informativeText = L("Die Karten werden aus allen Gruppen und aus „\(srcs)“ gelöscht.", "The cards will be removed from all groups and from “\(srcs)”.")
        a.addButton(withTitle: L("Löschen", "Delete")); a.addButton(withTitle: L("Abbrechen", "Cancel"))
        guard a.runModal() == .alertFirstButtonReturn else { return }
        for p in ps { if !store.delete(p) { let e = NSAlert(); e.messageText = L("Löschen fehlgeschlagen", "Delete failed"); e.informativeText = store.lastError ?? ""; e.runModal(); break } }
        selectedIDs = []; store.reload(); reloadAll()
    }

    // MARK: groups

    @objc func plusPressed() { newCard() }
    func plusMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem(withTitle: L("Neue Karte", "New Card"), action: #selector(newCard), keyEquivalent: "").target = self
        m.addItem(withTitle: L("Neue Gruppe", "New Group"), action: #selector(newGroup), keyEquivalent: "").target = self
        m.addItem(withTitle: L("Neue intelligente Gruppe …", "New Smart Group…"), action: #selector(newSmartGroup), keyEquivalent: "").target = self
        return m
    }

    func ask(_ title: String, value: String = "", ok: String = "OK") -> String? {
        let a = NSAlert(); a.messageText = title; a.addButton(withTitle: ok); a.addButton(withTitle: L("Abbrechen", "Cancel"))
        let t = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 22)); t.stringValue = value; a.accessoryView = t
        a.window.initialFirstResponder = t
        guard a.runModal() == .alertFirstButtonReturn, !t.stringValue.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return t.stringValue.trimmingCharacters(in: .whitespaces)
    }

    @objc func newGroup() {
        guard let n = ask(L("Name der neuen Gruppe", "New Group Name")) else { return }
        var cid: String? = nil
        switch source {
        case .container(let id): cid = id
        case .group(let id): cid = store.groups.first { $0.id == id }?.containerID
        default: cid = store.demo ? "icloud" : store.cn.defaultContainerIdentifier()
        }
        if !store.addGroup(named: n, in: cid) { let e = NSAlert(); e.messageText = L("Gruppe konnte nicht angelegt werden", "Couldn't create the group"); e.informativeText = store.lastError ?? ""; e.runModal() }
        reloadAll()
    }

    @objc func newSmartGroup() { editSmartGroup(nil) }
    func editSmartGroup(_ g: SmartGroup?) {
        guard let r = SmartGroupEditor.run(g, parent: window) else { return }
        if let i = store.smartGroups.firstIndex(where: { $0.id == r.id }) { store.smartGroups[i] = r } else { store.smartGroups.append(r) }
        source = .smart(r.id); reloadAll()
    }

    func groupMenu(_ it: Sidebar.Item) -> NSMenu? {
        let m = NSMenu()
        func add(_ t: String, _ f: @escaping () -> Void) {
            let i = NSMenuItem(title: t, action: #selector(runBlock(_:)), keyEquivalent: ""); i.target = self; i.representedObject = f; m.addItem(i)
        }
        switch it {
        case .group(let g):
            add(L("Gruppe umbenennen …", "Rename Group…")) { [weak self] in if let n = self?.ask(L("Gruppe umbenennen", "Rename Group"), value: g.name) { self?.store.renameGroup(g, to: n); self?.reloadAll() } }
            add(L("Gruppe löschen (Kontakte bleiben erhalten)", "Delete Group (cards are kept)")) { [weak self] in self?.store.deleteGroup(g); self?.reloadAll() }
            if !selectedIDs.isEmpty && store.groups.first(where: { $0.id == g.id })?.members.isDisjoint(with: selectedIDs) == false {
                add(L("Auswahl aus Gruppe entfernen", "Remove Selection from Group")) { [weak self] in guard let s = self else { return }; s.store.remove(s.selectedIDs, from: g); s.reloadAll() }
            }
        case .smart(let g):
            add(L("Intelligente Gruppe bearbeiten …", "Edit Smart Group…")) { [weak self] in self?.editSmartGroup(g) }
            add(L("Intelligente Gruppe löschen", "Delete Smart Group")) { [weak self] in self?.store.smartGroups.removeAll { $0.id == g.id }; self?.reloadAll() }
        default: return nil
        }
        return m
    }
    @objc func runBlock(_ i: NSMenuItem) { (i.representedObject as? () -> Void)?() }

    @objc func removeFromGroup() {
        guard case .group(let id) = source, let g = store.groups.first(where: { $0.id == id }), !selectedIDs.isEmpty else { return }
        store.remove(selectedIDs, from: g); reloadAll()
    }

    func sourceMenu() -> NSMenu {
        let m = NSMenu()
        func add(_ t: String, _ s: Source, indent: Int = 0) {
            let i = NSMenuItem(title: t, action: #selector(pickSource(_:)), keyEquivalent: ""); i.target = self; i.representedObject = SourceBox(s); i.indentationLevel = indent
            if s == source { i.state = .on }; m.addItem(i)
        }
        add(L("Alle Kontakte", "All Contacts"), .all)
        for c in store.containers {
            let gs = store.groups.filter { $0.containerID == c.id }
            m.addItem(.separator()); let h = NSMenuItem(title: c.name.uppercased(), action: nil, keyEquivalent: ""); h.isEnabled = false; m.addItem(h)
            if store.containers.count > 1 { add(L("Alle ", "All ") + c.name, .container(c.id), indent: 1) }
            gs.sorted { $0.name < $1.name }.forEach { add($0.name, .group($0.id), indent: 1) }
        }
        if !store.smartGroups.isEmpty {
            m.addItem(.separator()); let h = NSMenuItem(title: L("INTELLIGENTE GRUPPEN", "SMART GROUPS"), action: nil, keyEquivalent: ""); h.isEnabled = false; m.addItem(h)
            store.smartGroups.forEach { add($0.name, .smart($0.id), indent: 1) }
        }
        return m
    }
    final class SourceBox: NSObject { let s: Source; init(_ s: Source) { self.s = s } }
    @objc func pickSource(_ i: NSMenuItem) { if let b = i.representedObject as? SourceBox { sourceSelected(b.s); sidebar.select(b.s) } }

    // MARK: share, vCard, print

    func selectedPeople() -> [Person] { store.people.filter { selectedIDs.contains($0.id) } }

    func shareMenu() -> NSMenu? {
        let ps = selectedPeople(); guard !ps.isEmpty, let data = store.vcard(ps) else { return nil }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("RetroContacts-Share", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = (ps.count == 1 ? ps[0].fullName : L("Kontakte", "Contacts")).replacingOccurrences(of: "/", with: "-")
        let url = dir.appendingPathComponent(name + ".vcf")
        guard (try? data.write(to: url)) != nil else { return nil }
        shareTemp = dir
        let m = NSMenu()
        for s in NSSharingService.sharingServices(forItems: [url]) {
            let i = NSMenuItem(title: s.menuItemTitle, action: #selector(runShare(_:)), keyEquivalent: ""); i.target = self
            i.image = s.image.copy() as? NSImage; i.image?.size = NSSize(width: 16, height: 16)
            i.representedObject = [s, url] as [Any]; m.addItem(i)
        }
        return m
    }
    @objc func runShare(_ i: NSMenuItem) {
        guard let a = i.representedObject as? [Any], let s = a[0] as? NSSharingService, let u = a[1] as? URL else { return }
        s.perform(withItems: [u])
    }
    func cleanupShare() { if let d = shareTemp { try? FileManager.default.removeItem(at: d) } }

    @objc func exportVCard() {
        let ps = selectedPeople().isEmpty ? visible : selectedPeople()
        guard !ps.isEmpty else { NSSound.beep(); return }
        let sp = NSSavePanel(); sp.allowedContentTypes = [UTType.vCard]; sp.nameFieldStringValue = (ps.count == 1 ? ps[0].fullName : L("Kontakte", "Contacts")) + ".vcf"
        let cb = NSButton(checkboxWithTitle: L("Fotos einschließen", "Include photos"), target: nil, action: nil); cb.state = .on
        let note = NSTextField(labelWithString: L("\(ps.count) Karte(n); Notizen werden nicht exportiert.", "\(ps.count) card(s); notes are not exported."))
        note.font = .systemFont(ofSize: 11); note.textColor = .secondaryLabelColor
        let box = NSStackView(views: [cb, note]); box.orientation = .vertical; box.alignment = .leading; box.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        sp.accessoryView = box
        guard sp.runModal() == .OK, let url = sp.url, let d = store.vcard(ps, photos: cb.state == .on) else { return }
        do { try d.write(to: url, options: .atomic) } catch { NSAlert(error: error).runModal() }
    }

    @objc func importVCard() {
        let op = NSOpenPanel(); op.allowedContentTypes = [UTType.vCard]; op.allowsMultipleSelection = true
        guard op.runModal() == .OK else { return }
        importFiles(op.urls)
    }
    func importFiles(_ urls: [URL]) {
        var total = 0; var datas: [Data] = []
        for u in urls { if let d = try? Data(contentsOf: u), d.count < 200_000_000 { datas.append(d); total += (try? CNContactVCardSerialization.contacts(with: d).count) ?? 0 } }
        guard total > 0 else { let a = NSAlert(); a.messageText = L("Keine Karten gefunden", "No cards found"); a.runModal(); return }
        var cid: String? = nil
        if case .container(let id) = source { cid = id } else if !store.demo { cid = store.cn.defaultContainerIdentifier() }
        let cname = store.containers.first { $0.id == cid }?.name ?? ""
        let a = NSAlert(); a.messageText = L("\(total) Karte(n) importieren?", "Import \(total) card(s)?")
        a.informativeText = L("Die Karten werden zu „\(cname)“ hinzugefügt. Bereits vorhandene Kontakte werden nicht überschrieben.", "The cards will be added to “\(cname)”. Existing contacts are not overwritten.")
        a.addButton(withTitle: L("Importieren", "Import")); a.addButton(withTitle: L("Abbrechen", "Cancel"))
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let n = datas.reduce(0) { $0 + store.importVCard($1, into: cid) }
        let r = NSAlert(); r.messageText = L("\(n) von \(total) Karte(n) importiert.", "\(n) of \(total) card(s) imported."); if n < total { r.informativeText = store.lastError ?? "" }; r.runModal()
        reloadAll()
    }

    @objc func printCards() {
        let ps = selectedPeople().isEmpty ? (visible.count > 0 ? visible : []) : selectedPeople()
        guard !ps.isEmpty else { NSSound.beep(); return }
        let out = NSMutableAttributedString()
        let pstyle = NSMutableParagraphStyle(); pstyle.paragraphSpacing = 2
        for p in ps {
            out.append(NSAttributedString(string: p.fullName + "\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 13), .paragraphStyle: pstyle]))
            var lines: [String] = []
            if !p.isCompany && !p.org.isEmpty { lines.append(p.org) }
            p.phones.forEach { lines.append("\(Labels.text($0.label)): \($0.value)") }
            p.emails.forEach { lines.append("\(Labels.text($0.label)): \($0.value)") }
            p.urls.forEach { lines.append("\(Labels.text($0.label)): \($0.value)") }
            p.addrs.forEach { lines.append("\(Labels.text($0.label)):\n" + CardView.formatAddress($0)) }
            if let b = p.birthday, let s = CardView.birthdayString(b) { lines.append("\(L("Geburtstag", "birthday")): \(s)") }
            out.append(NSAttributedString(string: lines.joined(separator: "\n") + (ps.count > 1 ? "\n\n" : "\n"), attributes: [.font: NSFont.systemFont(ofSize: 11)]))
        }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.leftMargin = 54; info.rightMargin = 54; info.topMargin = 54; info.bottomMargin = 54
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: info.paperSize.width - 108, height: 100))
        tv.textStorage?.setAttributedString(out); tv.sizeToFit()
        let op = NSPrintOperation(view: tv, printInfo: info); op.jobTitle = L("Kontakte", "Contacts")
        op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    @objc func findField() { window.makeFirstResponder(search.field) }
}

extension ContactList {
    func firstPersonID() -> String? { for r in rows { if case .person(let p) = r { return p.id } }; return nil }
}

// MARK: - Smart group editor (name, all/any, rows of field / operator / value)

import Contacts
final class SmartGroupEditor: NSObject {
    var g: SmartGroup
    let panel: NSPanel
    let nameField = NSTextField()
    let matchPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let content = NSView()
    var done = false

    init(_ g: SmartGroup) {
        self.g = g
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 540, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        super.init()
        panel.title = L("Intelligente Gruppe", "Smart Group")
    }

    static func run(_ g: SmartGroup?, parent: NSWindow) -> SmartGroup? {
        let e = SmartGroupEditor(g ?? SmartGroup(name: L("Intelligente Gruppe", "Smart Group")))
        e.build(); e.panel.center()
        NSApp.runModal(for: e.panel); e.panel.orderOut(nil)
        return e.done ? e.g : nil
    }

    func build() {
        let cv = panel.contentView!; cv.subviews.forEach { $0.removeFromSuperview() }
        var y: CGFloat = 16
        let nl = NSTextField(labelWithString: L("Name:", "Name:")); nl.frame = NSRect(x: 16, y: 0, width: 50, height: 17); nameField.stringValue = g.name
        nameField.frame = NSRect(x: 70, y: 0, width: 454, height: 22)
        let rows = g.rules.count
        let total = 16 + 30 + 30 + CGFloat(rows) * 30 + 54
        panel.setContentSize(NSSize(width: 540, height: total))
        func fy(_ top: CGFloat, _ h: CGFloat) -> CGFloat { total - top - h }
        nl.frame.origin.y = fy(y + 3, 17); nameField.frame.origin.y = fy(y, 22); cv.addSubview(nl); cv.addSubview(nameField); y += 32
        let l1 = NSTextField(labelWithString: L("Karten, die", "Cards which match")); l1.frame = NSRect(x: 16, y: fy(y + 2, 17), width: 90, height: 17); cv.addSubview(l1)
        matchPopup.removeAllItems(); matchPopup.addItems(withTitles: [L("alle", "all"), L("mindestens eine", "any")]); matchPopup.selectItem(at: g.matchAll ? 0 : 1)
        matchPopup.frame = NSRect(x: 100, y: fy(y, 22), width: 140, height: 22); matchPopup.target = self; matchPopup.action = #selector(matchChanged); cv.addSubview(matchPopup)
        let l2 = NSTextField(labelWithString: L("der folgenden Bedingungen erfüllen:", "of the following conditions:")); l2.frame = NSRect(x: 248, y: fy(y + 2, 17), width: 280, height: 17); cv.addSubview(l2); y += 30
        for (i, r) in g.rules.enumerated() {
            let f = NSPopUpButton(frame: NSRect(x: 16, y: fy(y, 22), width: 120, height: 22), pullsDown: false); f.addItems(withTitles: SmartGroup.fields); f.selectItem(at: r.field); f.tag = i; f.target = self; f.action = #selector(fieldChanged(_:))
            let o = NSPopUpButton(frame: NSRect(x: 142, y: fy(y, 22), width: 120, height: 22), pullsDown: false); o.addItems(withTitles: SmartGroup.ops); o.selectItem(at: r.op); o.tag = i; o.target = self; o.action = #selector(opChanged(_:))
            let v = NSTextField(frame: NSRect(x: 268, y: fy(y, 22), width: 180, height: 22)); v.stringValue = r.value; v.tag = i; v.isHidden = r.op == 3; v.target = self; v.action = #selector(valueChanged(_:))
            v.delegate = self
            let minus = RetroButton(glyph: { rr, c in c.setStroke(); let p = NSBezierPath(); p.lineWidth = 1.6; p.move(to: NSPoint(x: rr.midX - 4, y: rr.midY)); p.line(to: NSPoint(x: rr.midX + 4, y: rr.midY)); p.stroke() })
            minus.frame = NSRect(x: 456, y: fy(y + 1, 21), width: 32, height: 21); minus.tag = i; minus.target = self; minus.action = #selector(removeRule(_:)); minus.isEnabled = g.rules.count > 1
            let plus = RetroButton(glyph: Glyph.plus); plus.frame = NSRect(x: 492, y: fy(y + 1, 21), width: 32, height: 21); plus.target = self; plus.action = #selector(addRule)
            [f, o, v, minus, plus].forEach { cv.addSubview($0) }; y += 30
        }
        let ok = NSButton(title: "OK", target: self, action: #selector(okPressed)); ok.keyEquivalent = "\r"; ok.frame = NSRect(x: 540 - 16 - 80, y: 14, width: 80, height: 28)
        let cancel = NSButton(title: L("Abbrechen", "Cancel"), target: self, action: #selector(cancelPressed)); cancel.keyEquivalent = "\u{1b}"; cancel.frame = NSRect(x: 540 - 16 - 80 - 90, y: 14, width: 90, height: 28)
        cv.addSubview(ok); cv.addSubview(cancel)
    }
    @objc func matchChanged() { g.matchAll = matchPopup.indexOfSelectedItem == 0 }
    @objc func fieldChanged(_ s: NSPopUpButton) { g.rules[s.tag].field = s.indexOfSelectedItem }
    @objc func opChanged(_ s: NSPopUpButton) { g.rules[s.tag].op = s.indexOfSelectedItem; syncName(); build() }
    @objc func valueChanged(_ s: NSTextField) { g.rules[s.tag].value = s.stringValue }
    @objc func removeRule(_ s: NSControl) { syncName(); g.rules.remove(at: s.tag); build() }
    @objc func addRule() { syncName(); g.rules.append(SmartRule()); build() }
    func syncName() { g.name = nameField.stringValue }
    @objc func okPressed() { panel.makeFirstResponder(nil); syncName(); if g.name.trimmingCharacters(in: .whitespaces).isEmpty { NSSound.beep(); return }; done = true; NSApp.stopModal() }
    @objc func cancelPressed() { NSApp.stopModal() }
}
extension SmartGroupEditor: NSTextFieldDelegate {
    func controlTextDidChange(_ n: Notification) { if let t = n.object as? NSTextField, t !== nameField, t.tag < g.rules.count { g.rules[t.tag].value = t.stringValue } }
}
