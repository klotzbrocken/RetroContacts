import Cocoa

let contactPasteboardType = NSPasteboard.PasteboardType("de.retrocontacts.ids")

enum Prefs {
    static var sortByFamily: Bool { get { UserDefaults.standard.object(forKey: "sortByFamily") as? Bool ?? false } set { UserDefaults.standard.set(newValue, forKey: "sortByFamily") } }
    static var displayFamilyFirst: Bool { get { UserDefaults.standard.bool(forKey: "displayFamilyFirst") } set { UserDefaults.standard.set(newValue, forKey: "displayFamilyFirst") } }
}

// MARK: - shared row view

final class RetroRowView: NSTableRowView {
    enum Kind { case header, person, side, sideHeader }
    var kind: Kind = .person
    override var isEmphasized: Bool { didSet { redrawAll() } }
    override var isSelected: Bool { didSet { redrawAll() } }
    private func redrawAll() { needsDisplay = true; subviews.forEach { $0.needsDisplay = true } }
    var strong: Bool { isSelected && isEmphasized && (window?.isKeyWindow ?? false) }

    override func drawBackground(in r: NSRect) {
        switch kind {
        case .header:
            gradient([NSColor(calibratedRed: 208 / 255, green: 210 / 255, blue: 211 / 255, alpha: 1), NSColor(calibratedRed: 227 / 255, green: 228 / 255, blue: 229 / 255, alpha: 1)]).draw(in: bounds, angle: -90)
            NSColor(calibratedWhite: 0.96, alpha: 1).setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: bounds.width, height: 1)).fill()
            NSColor(calibratedWhite: 0.86, alpha: 1).setFill(); NSBezierPath(rect: NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)).fill()
        case .person:
            NSColor.white.setFill(); bounds.fill()
            dotted(y: bounds.height - 1, width: bounds.width)
        default: break
        }
    }
    func dotted(y: CGFloat, width: CGFloat) {
        NSColor(calibratedWhite: 0.76, alpha: 1).setFill()
        var x: CGFloat = 0
        while x < width { NSRect(x: x, y: y, width: 1, height: 1).fill(); x += 2 }
    }
    override func draw(_ r: NSRect) {
        super.draw(r)
        if kind == .person && isSelected { dotted(y: bounds.height - 1, width: bounds.width) }
    }
    override func drawSelection(in r: NSRect) {
        guard kind == .person else { return }
        if strong {
            gradient([NSColor(calibratedRed: 0.36, green: 0.58, blue: 0.88, alpha: 1), NSColor(calibratedRed: 0.17, green: 0.40, blue: 0.78, alpha: 1)]).draw(in: bounds, angle: -90)
        } else { Pal.selPale.setFill(); bounds.fill(); NSColor(calibratedRed: 0.86, green: 0.89, blue: 0.95, alpha: 1).setFill(); NSBezierPath(rect: NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)).fill() }
    }
}

final class TextCell: NSView {
    var text = NSAttributedString() { didSet { needsDisplay = true } }
    var indent: CGFloat = 6
    override var isFlipped: Bool { true }
    override func draw(_ dirty: NSRect) {
        guard let row = superview as? RetroRowView else { return }
        let t = NSMutableAttributedString(attributedString: text)
        let full = NSRange(location: 0, length: t.length)
        switch row.kind {
        case .person:
            if row.isSelected { t.addAttribute(.foregroundColor, value: row.strong ? NSColor.white : Pal.selBlueText, range: full) }
            else { t.addAttribute(.foregroundColor, value: NSColor.black, range: full) }
        case .header: t.addAttribute(.foregroundColor, value: Pal.selBlueText, range: full)
        case .side:
            let sel = row.isSelected
            t.addAttribute(.foregroundColor, value: sel ? Pal.sideBlue : NSColor(calibratedWhite: 0.1, alpha: 1), range: full)
            if sel { t.addAttribute(.font, value: Fonts.bold(12), range: full) }
        case .sideHeader: t.addAttribute(.foregroundColor, value: NSColor(calibratedWhite: 0.55, alpha: 1), range: full)
        }
        let h = t.size().height
        let r = NSRect(x: indent, y: (bounds.height - h) / 2, width: bounds.width - indent - 4, height: h)
        t.draw(with: r, options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin])
    }
}

func retroScroll(_ doc: NSView) -> NSScrollView {
    let s = NSScrollView(); s.documentView = doc
    s.hasVerticalScroller = true; s.hasHorizontalScroller = false; s.scrollerStyle = .legacy; s.autohidesScrollers = true
    s.drawsBackground = false; s.borderType = .noBorder
    s.verticalScroller?.controlSize = .small
    return s
}

// MARK: - contact list

final class ContactList: NSView, NSTableViewDataSource, NSTableViewDelegate {
    enum Row { case header(String), person(Person) }
    let table = ListTable()
    let scroll: NSScrollView
    let empty = NSTextField(labelWithString: "")
    var rows: [Row] = []
    var onSelect: (([String]) -> Void)?
    var onDoubleClick: (() -> Void)?
    var emptyText = "" { didSet { empty.stringValue = emptyText; empty.isHidden = !rows.isEmpty || emptyText.isEmpty } }
    override var isFlipped: Bool { true }
    private var suppress = false

    override init(frame: NSRect) {
        scroll = retroScroll(table)
        super.init(frame: frame)
        let col = NSTableColumn(identifier: .init("c")); col.resizingMask = .autoresizingMask
        table.addTableColumn(col); table.headerView = nil
        table.intercellSpacing = .zero; table.rowHeight = 26; table.drawsRuledFiller = true; table.backgroundColor = .white
        table.allowsMultipleSelection = true; table.floatsGroupRows = false
        table.style = .plain; table.focusRingType = .none
        table.dataSource = self; table.delegate = self
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        table.doubleAction = #selector(dbl); table.target = self
        table.setAccessibilityLabel(L("Kontaktliste", "Contact list"))
        addSubview(scroll)
        empty.font = Fonts.regular(11); empty.textColor = Pal.labelGrey; empty.alignment = .center; empty.isHidden = true
        addSubview(empty)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); scroll.frame = bounds.insetBy(dx: 1, dy: 1); table.sizeLastColumnToFit(); empty.frame = NSRect(x: 8, y: bounds.height / 2 - 20, width: bounds.width - 16, height: 40) }
    @objc func dbl() { onDoubleClick?() }

    override func draw(_ dirty: NSRect) {
        NSColor.white.setFill(); bounds.fill()
        NSColor(calibratedWhite: 0.80, alpha: 1).setStroke(); NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)).stroke()
        NSColor(calibratedWhite: 0.72, alpha: 1).setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: bounds.width, height: 1)).fill()
    }

    var selectedIDs: [String] {
        table.selectedRowIndexes.compactMap { if case .person(let p) = rows[$0] { return p.id } else { return nil } }
    }

    func setPeople(_ ppl: [Person], keepSelection ids: [String]? = nil) {
        let keep = ids ?? selectedIDs
        let fam = Prefs.sortByFamily
        let sorted = ppl.sorted { a, b in
            let ka = sectionLetter(a), kb = sectionLetter(b)
            if ka != kb { return ka == "#" ? false : kb == "#" ? true : ka < kb }
            let c = a.sortKey(byFamily: fam).localizedStandardCompare(b.sortKey(byFamily: fam))
            return c == .orderedSame ? a.id < b.id : c == .orderedAscending
        }
        var out: [Row] = []; var cur = ""
        for p in sorted { let l = sectionLetter(p); if l != cur { cur = l; out.append(.header(l)) }; out.append(.person(p)) }
        rows = out
        suppress = true; table.reloadData()
        table.selectRowIndexes(IndexSet(out.indices.filter { if case .person(let p) = out[$0] { return keep.contains(p.id) } else { return false } }), byExtendingSelection: false)
        suppress = false
        empty.isHidden = !rows.isEmpty || emptyText.isEmpty
    }

    private func sectionLetter(_ p: Person) -> String {
        let k = p.sortKey(byFamily: Prefs.sortByFamily)
        guard let c = k.folding(options: [.diacriticInsensitive], locale: .current).uppercased().first, c.isLetter else { return "#" }
        return String(c)
    }

    func select(id: String?, scroll sc: Bool = true) {
        guard let id = id, let i = rows.firstIndex(where: { if case .person(let p) = $0 { return p.id == id } else { return false } }) else { table.deselectAll(nil); return }
        suppress = true; table.selectRowIndexes([i], byExtendingSelection: false); suppress = false
        if sc { table.scrollRowToVisible(i <= 1 ? 0 : i) }
    }
    func selectAdjacent(_ d: Int) {
        let idx = table.selectedRow
        var i = idx + d
        while i >= 0 && i < rows.count { if case .person = rows[i] { table.selectRowIndexes([i], byExtendingSelection: false); table.scrollRowToVisible(i); return }; i += d }
    }
    func canMove(_ d: Int) -> Bool {
        var i = table.selectedRow + d
        if table.selectedRow < 0 { return false }
        while i >= 0 && i < rows.count { if case .person = rows[i] { return true }; i += d }
        return false
    }

    // data source / delegate
    func numberOfRows(in t: NSTableView) -> Int { rows.count }
    func tableView(_ t: NSTableView, isGroupRow r: Int) -> Bool { if case .header = rows[r] { return true }; return false }
    func tableView(_ t: NSTableView, shouldSelectRow r: Int) -> Bool { if case .person = rows[r] { return true }; return false }
    func tableView(_ t: NSTableView, heightOfRow r: Int) -> CGFloat { if case .header = rows[r] { return 17 }; return 26 }
    func tableView(_ t: NSTableView, rowViewForRow r: Int) -> NSTableRowView? {
        let v = RetroRowView(); if case .header = rows[r] { v.kind = .header } else { v.kind = .person }; return v
    }
    func tableView(_ t: NSTableView, viewFor c: NSTableColumn?, row r: Int) -> NSView? {
        let cell = TextCell()
        switch rows[r] {
        case .header(let l): cell.text = NSAttributedString(string: l, attributes: [.font: Fonts.bold(11)])
        case .person(let p): cell.text = p.listTitle(displayFamilyFirst: Prefs.displayFamilyFirst, boldFamily: Prefs.sortByFamily); cell.setAccessibilityLabel(p.fullName)
        }
        return cell
    }
    func tableViewSelectionDidChange(_ n: Notification) { if !suppress { onSelect?(selectedIDs) } }
    func tableView(_ t: NSTableView, pasteboardWriterForRow r: Int) -> NSPasteboardWriting? {
        guard case .person(let p) = rows[r] else { return nil }
        let item = NSPasteboardItem()
        // dragging a row that is part of the selection drags the whole selection
        let ids = selectedIDs.contains(p.id) ? selectedIDs : [p.id]
        item.setString(ids.joined(separator: "\n"), forType: contactPasteboardType)
        return item
    }
}

final class ListTable: NSTableView {
    /// empty lower area keeps the ruled-paper dotted lines, like the original
    override func drawBackground(inClipRect r: NSRect) {
        super.drawBackground(inClipRect: r)
        guard drawsRuledFiller else { return }
        let start = numberOfRows > 0 ? rect(ofRow: numberOfRows - 1).maxY : 0
        NSColor(calibratedWhite: 0.76, alpha: 1).setFill()
        var y = start + 25
        while y < r.maxY { if y + 1 > r.minY { var x = r.minX; while x < r.maxX { NSRect(x: x, y: y, width: 1, height: 1).fill(); x += 2 } }; y += 26 }
    }
    var drawsRuledFiller = false
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { let r = super.becomeFirstResponder(); refreshEmphasis(); return r }
    override func resignFirstResponder() -> Bool { let r = super.resignFirstResponder(); refreshEmphasis(); return r }
    func refreshEmphasis() { enumerateAvailableRowViews { v, _ in v.isEmphasized = (self.window?.firstResponder === self) } }
    override var mouseDownCanMoveWindow: Bool { false }
    var menuProvider: ((NSEvent) -> NSMenu?)?
    override func menu(for e: NSEvent) -> NSMenu? { menuProvider?(e) ?? super.menu(for: e) }
}

// MARK: - sidebar

enum Source: Equatable {
    case all, container(String), group(String), smart(String)
}

final class Sidebar: NSView, NSTableViewDataSource, NSTableViewDelegate {
    enum Item { case header(String), all, container(Container), group(Group), smart(SmartGroup) }
    let table = ListTable(); let scroll: NSScrollView
    var items: [Item] = []
    var onSelect: ((Source) -> Void)?
    var onMenu: ((Item) -> NSMenu?)?
    var onDrop: ((Group, [String]) -> Bool)?
    override var isFlipped: Bool { true }
    private var suppress = false

    override init(frame: NSRect) {
        scroll = retroScroll(table)
        super.init(frame: frame)
        let col = NSTableColumn(identifier: .init("c")); col.resizingMask = .autoresizingMask
        table.addTableColumn(col); table.headerView = nil; table.intercellSpacing = .zero; table.rowHeight = 19
        table.backgroundColor = .clear; table.style = .plain; table.focusRingType = .none
        table.dataSource = self; table.delegate = self
        table.registerForDraggedTypes([contactPasteboardType])
        table.setAccessibilityLabel(L("Gruppen", "Groups"))
        table.menuProvider = { [weak self] e in
            guard let self = self else { return nil }
            let r = self.table.row(at: self.table.convert(e.locationInWindow, from: nil))
            return r >= 0 ? self.onMenu?(self.items[r]) : nil
        }
        addSubview(scroll)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); scroll.frame = bounds; table.sizeLastColumnToFit() }

    func reload(selecting s: Source) {
        let st = Store.shared
        var it: [Item] = [.all]
        let multi = st.containers.count > 1
        for c in st.containers {
            let gs = st.groups.filter { $0.containerID == c.id }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            if gs.isEmpty && !multi { continue }
            if multi { it.append(.header(c.name.uppercased())) }
            if multi { it.append(.container(c)) }
            gs.forEach { it.append(.group($0)) }
        }
        if !st.smartGroups.isEmpty { it.append(.header(L("INTELLIGENTE GRUPPEN", "SMART GROUPS"))); st.smartGroups.forEach { it.append(.smart($0)) } }
        items = it
        suppress = true; table.reloadData(); select(s); suppress = false
    }

    func select(_ s: Source) {
        let i = items.firstIndex { item in
            switch (item, s) {
            case (.all, .all): return true
            case (.container(let c), .container(let id)): return c.id == id
            case (.group(let g), .group(let id)): return g.id == id
            case (.smart(let g), .smart(let id)): return g.id == id
            default: return false
            }
        } ?? 0
        suppress = true; table.selectRowIndexes([i], byExtendingSelection: false); suppress = false
    }

    func source(of item: Item) -> Source? {
        switch item { case .all: return .all; case .container(let c): return .container(c.id); case .group(let g): return .group(g.id); case .smart(let g): return .smart(g.id); default: return nil }
    }

    func numberOfRows(in t: NSTableView) -> Int { items.count }
    func tableView(_ t: NSTableView, shouldSelectRow r: Int) -> Bool { if case .header = items[r] { return false }; return true }
    func tableView(_ t: NSTableView, heightOfRow r: Int) -> CGFloat { if case .header = items[r] { return 22 }; return 19 }
    func tableView(_ t: NSTableView, rowViewForRow r: Int) -> NSTableRowView? {
        let v = RetroRowView(); if case .header = items[r] { v.kind = .sideHeader } else { v.kind = .side }; return v
    }
    func tableView(_ t: NSTableView, viewFor c: NSTableColumn?, row r: Int) -> NSView? {
        let cell = TextCell(); cell.indent = 27
        let f = Fonts.regular(12)
        switch items[r] {
        case .header(let s): cell.text = NSAttributedString(string: s, attributes: [.font: Fonts.bold(10)]); cell.indent = 18
        case .all: cell.text = NSAttributedString(string: L("Alle Kontakte", "All Contacts"), attributes: [.font: f])
        case .container(let c): cell.text = NSAttributedString(string: L("Alle ", "All ") + c.name, attributes: [.font: f])
        case .group(let g): cell.text = NSAttributedString(string: g.name, attributes: [.font: f])
        case .smart(let g): cell.text = NSAttributedString(string: g.name, attributes: [.font: f])
        }
                return cell
    }
    func tableViewSelectionDidChange(_ n: Notification) {
        guard !suppress, table.selectedRow >= 0, let s = source(of: items[table.selectedRow]) else { return }
        onSelect?(s)
    }
    // drop contacts on a group
    func tableView(_ t: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation op: NSTableView.DropOperation) -> NSDragOperation {
        guard row < items.count, case .group = items[row] else { return [] }
        t.setDropRow(row, dropOperation: .on); return .copy
    }
    func tableView(_ t: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation op: NSTableView.DropOperation) -> Bool {
        guard case .group(let g) = items[row], let s = info.draggingPasteboard.string(forType: contactPasteboardType) else { return false }
        return onDrop?(g, s.components(separatedBy: "\n")) ?? false
    }
}
