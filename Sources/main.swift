import Cocoa
import UniformTypeIdentifiers

// MARK: - App icon override (user-chosen 256×256 PNG)

enum AppIcon {
    static var dir: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("RetroContacts")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true); return u
    }
    static var file: URL { dir.appendingPathComponent("AppIcon.png") }
    static var custom: NSImage? { NSImage(contentsOf: file) }

    /// the system default (bundle) icon
    static var bundled: NSImage? { NSImage(named: "AppIcon") ?? NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath) }

    static func apply() {
        if let img = custom {
            NSApp.applicationIconImage = img      // Dock icon while running (the signed bundle itself is never modified)
        } else {
            NSApp.applicationIconImage = nil
        }
    }

    /// returns an error text, or nil on success
    static func install(_ url: URL) -> String? {
        guard url.pathExtension.lowercased() == "png", let data = try? Data(contentsOf: url), data.starts(with: [0x89, 0x50, 0x4E, 0x47]),
              let rep = NSBitmapImageRep(data: data) else { return L("Die Datei ist kein PNG-Bild.", "The file is not a PNG image.") }
        guard rep.pixelsWide == 256 && rep.pixelsHigh == 256 else {
            return L("Das Bild ist \(rep.pixelsWide) × \(rep.pixelsHigh) Pixel groß. Benötigt wird exakt 256 × 256 Pixel.", "The image is \(rep.pixelsWide) × \(rep.pixelsHigh) pixels. Exactly 256 × 256 pixels are required.")
        }
        do { try data.write(to: file, options: .atomic) } catch { return error.localizedDescription }
        apply(); return nil
    }
    static func reset() { try? FileManager.default.removeItem(at: file); apply() }
}

// MARK: - Preferences

final class PrefsController: NSObject {
    static let shared = PrefsController()
    let window: NSWindow
    let iconView = NSImageView()
    let status = NSTextField(labelWithString: "")
    let access = NSTextField(labelWithString: "")
    let sortPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    let displayPopup = NSPopUpButton(frame: .zero, pullsDown: false)

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 470, height: 330), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = L("Einstellungen", "Preferences"); window.isReleasedWhenClosed = false
        let cv = window.contentView!
        func label(_ s: String, _ y: CGFloat, bold: Bool = false) -> NSTextField {
            let t = NSTextField(labelWithString: s); t.font = bold ? .boldSystemFont(ofSize: 13) : .systemFont(ofSize: 13); t.frame = NSRect(x: 20, y: y, width: 200, height: 17); cv.addSubview(t); return t
        }
        _ = label(L("Darstellung", "Appearance"), 296, bold: true)
        let l1 = label(L("Sortieren nach:", "Sort by:"), 268); l1.alignment = .right; l1.frame = NSRect(x: 20, y: 268, width: 110, height: 17)
        sortPopup.addItems(withTitles: [L("Nachname", "Last Name"), L("Vorname", "First Name")]); sortPopup.frame = NSRect(x: 138, y: 264, width: 200, height: 25)
        sortPopup.selectItem(at: Prefs.sortByFamily ? 0 : 1); sortPopup.target = self; sortPopup.action = #selector(changed); cv.addSubview(sortPopup)
        let l2 = label(L("Anzeigen als:", "Display as:"), 236); l2.alignment = .right; l2.frame = NSRect(x: 20, y: 236, width: 110, height: 17)
        displayPopup.addItems(withTitles: [L("Vorname Nachname", "First Last"), L("Nachname, Vorname", "Last, First")]); displayPopup.frame = NSRect(x: 138, y: 232, width: 200, height: 25)
        displayPopup.selectItem(at: Prefs.displayFamilyFirst ? 1 : 0); displayPopup.target = self; displayPopup.action = #selector(changed); cv.addSubview(displayPopup)

        let sep = NSBox(frame: NSRect(x: 20, y: 218, width: 430, height: 1)); sep.boxType = .separator; cv.addSubview(sep)
        _ = label(L("Programmsymbol", "App Icon"), 190, bold: true)
        iconView.frame = NSRect(x: 24, y: 78, width: 100, height: 100); iconView.imageScaling = .scaleProportionallyUpOrDown; cv.addSubview(iconView)
        let info = NSTextField(wrappingLabelWithString: L("Wählen Sie ein PNG-Bild mit genau 256 × 256 Pixeln. Es wird als Programmsymbol im Dock verwendet, solange RetroContacts läuft.", "Choose a PNG image of exactly 256 × 256 pixels. It is used as the Dock icon while RetroContacts is running."))
        info.font = .systemFont(ofSize: 12); info.textColor = .secondaryLabelColor; info.frame = NSRect(x: 140, y: 126, width: 310, height: 50); cv.addSubview(info)
        let choose = NSButton(title: L("PNG wählen …", "Choose PNG…"), target: self, action: #selector(choosePNG)); choose.frame = NSRect(x: 138, y: 92, width: 130, height: 28); cv.addSubview(choose)
        let reset = NSButton(title: L("Zurücksetzen", "Reset"), target: self, action: #selector(resetIcon)); reset.frame = NSRect(x: 272, y: 92, width: 120, height: 28); cv.addSubview(reset)
        status.frame = NSRect(x: 140, y: 70, width: 310, height: 17); status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor; cv.addSubview(status)

        let sep2 = NSBox(frame: NSRect(x: 20, y: 56, width: 430, height: 1)); sep2.boxType = .separator; cv.addSubview(sep2)
        _ = label(L("Systemkontakte", "System Contacts"), 28, bold: true)
        access.font = .systemFont(ofSize: 12); access.frame = NSRect(x: 140, y: 29, width: 200, height: 16); cv.addSubview(access)
        let open = NSButton(title: L("Systemeinstellungen …", "System Settings…"), target: self, action: #selector(openPrivacy)); open.frame = NSRect(x: 275, y: 22, width: 180, height: 28); cv.addSubview(open)
        iconView.setAccessibilityLabel(L("Aktuelles Programmsymbol", "Current app icon"))
    }
    func show() {
        refresh(); window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func refresh() {
        iconView.image = AppIcon.custom ?? NSApp.applicationIconImage
        status.stringValue = AppIcon.custom != nil ? L("Eigenes Symbol aktiv", "Custom icon active") : L("Standardsymbol aktiv", "Default icon active")
        access.stringValue = Store.shared.demo ? L("Demo-Daten", "Demo data") : (Store.shared.access == .granted ? L("Zugriff erlaubt", "Access allowed") : L("Kein Zugriff", "No access"))
    }
    @objc func changed() {
        Prefs.sortByFamily = sortPopup.indexOfSelectedItem == 0; Prefs.displayFamilyFirst = displayPopup.indexOfSelectedItem == 1
        NotificationCenter.default.post(name: .prefsChanged, object: nil)
    }
    @objc func choosePNG() {
        let p = NSOpenPanel(); p.allowedContentTypes = [UTType.png]; p.message = L("PNG-Bild mit 256 × 256 Pixeln wählen", "Choose a 256 × 256 pixel PNG image")
        guard p.runModal() == .OK, let u = p.url else { return }
        if let err = AppIcon.install(u) {
            let a = NSAlert(); a.alertStyle = .warning; a.messageText = L("Das Symbol kann nicht verwendet werden", "The icon can't be used"); a.informativeText = err; a.runModal()
        }
        refresh()
    }
    @objc func resetIcon() { AppIcon.reset(); refresh() }
    @objc func openPrivacy() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts")!) }
}

// MARK: - App delegate and menus

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    var main: MainController!

    func applicationDidFinishLaunching(_ n: Notification) {
        if CommandLine.arguments.contains("--selftest") { exit(SelfTest.run()) }
        Store.shared.demo = CommandLine.arguments.contains("--demo")
        NSApp.setActivationPolicy(.regular)
        AppIcon.apply()
        buildMenus()
        main = MainController()
        if let i = CommandLine.arguments.firstIndex(of: "--mode"), i + 1 < CommandLine.arguments.count, let m = Int(CommandLine.arguments[i + 1]), let vm = ViewMode(rawValue: m) { main.setMode(vm) }
        main.start()
        NSApp.activate(ignoringOtherApps: true)
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count { snapshot(CommandLine.arguments[i + 1]) }
    }

    func snapshot(_ path: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [self] in
            let args = CommandLine.arguments
            if let i = args.firstIndex(of: "--size"), i + 1 < args.count { let p = args[i + 1].split(separator: "x").compactMap { Double($0) }; if p.count == 2 { var f = main.window.frame; f.size = NSSize(width: p[0], height: p[1]); main.window.setFrame(f, display: true) } }
            if args.contains("--new") { main.newCard() }
            if let i = args.firstIndex(of: "--select"), i + 1 < args.count, let p = self.main.store.people.first(where: { $0.fullName == args[i + 1] }) { self.main.list.select(id: p.id); self.main.listSelected([p.id]) }
            if args.contains("--prefs") { PrefsController.shared.show() }
            if args.contains("--edit") { main.toggleEdit() }
            if let i = args.firstIndex(of: "--search"), i + 1 < args.count { main.search.text = args[i + 1]; main.searchChanged(args[i + 1]) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if args.contains("--prefs") { PrefsController.shared.window.contentView?.layoutSubtreeIfNeeded(); let cv = PrefsController.shared.window.contentView!; if let r = cv.bitmapImageRepForCachingDisplay(in: cv.bounds) { cv.cacheDisplay(in: cv.bounds, to: r); try? r.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path)) }; exit(0) }
                let v = self.main.book
                v.layoutSubtreeIfNeeded()
                guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { exit(1) }
                v.cacheDisplay(in: v.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                exit(0)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ a: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ a: NSApplication, hasVisibleWindows f: Bool) -> Bool { main.window.makeKeyAndOrderFront(nil); return true }
    func applicationWillTerminate(_ n: Notification) { main?.cleanupShare() }
    func application(_ a: NSApplication, open urls: [URL]) { main.importFiles(urls.filter { $0.pathExtension.lowercased() == "vcf" }) }
    func applicationShouldTerminate(_ s: NSApplication) -> NSApplication.TerminateReply {
        if main.editing && !main.confirmLeave() { return .terminateCancel }
        return .terminateNow
    }

    func validateMenuItem(_ i: NSMenuItem) -> Bool {
        guard let m = main else { return true }
        switch i.action {
        case #selector(menuDelete): return !m.selectedIDs.isEmpty && !m.editing
        case #selector(menuEdit): return m.selectedIDs.count == 1 || m.editing
        case #selector(menuRemoveFromGroup): if case .group = m.source { return !m.selectedIDs.isEmpty }; return false
        case #selector(menuPrev): return m.list.canMove(-1) && !m.editing
        case #selector(menuNext): return m.list.canMove(1) && !m.editing
        default: return true
        }
    }

    @objc func menuNew() { main.newCard() }
    @objc func menuNewGroup() { main.newGroup() }
    @objc func menuNewSmart() { main.newSmartGroup() }
    @objc func menuDelete() { main.deleteCard() }
    @objc func menuEdit() { main.toggleEdit() }
    @objc func menuImport() { main.importVCard() }
    @objc func menuExport() { main.exportVCard() }
    @objc func menuPrint() { main.printCards() }
    @objc func menuFind() { main.findField() }
    @objc func menuRemoveFromGroup() { main.removeFromGroup() }
    @objc func menuPrev() { main.previousCard() }
    @objc func menuNext() { main.nextCard() }
    @objc func menuMode(_ s: NSMenuItem) { main.setMode(ViewMode(rawValue: s.tag)!) }
    @objc func menuPrefs() { PrefsController.shared.show() }
    @objc func menuMinimize() { main.window.miniaturize(nil) }
    @objc func menuZoom() { main.window.toggleZoom() }
    @objc func menuShowWindow() { main.window.makeKeyAndOrderFront(nil) }
    @objc func menuAbout() { NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "RetroContacts"]) }

    func buildMenus() {
        let bar = NSMenu(); NSApp.mainMenu = bar
        func top(_ title: String) -> NSMenu {
            let item = NSMenuItem(); bar.addItem(item); let m = NSMenu(title: title); item.submenu = m; return m
        }
        @discardableResult func add(_ m: NSMenu, _ t: String, _ a: Selector?, _ k: String = "", _ mods: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
            let i = m.addItem(withTitle: t, action: a, keyEquivalent: k); i.keyEquivalentModifierMask = mods; i.target = target ?? (a != nil && "\(a!)".hasPrefix("menu") ? self : nil); return i
        }
        let app = top("RetroContacts")
        add(app, L("Über RetroContacts", "About RetroContacts"), #selector(menuAbout))
        app.addItem(.separator())
        add(app, L("Einstellungen …", "Preferences…"), #selector(menuPrefs), ",")
        app.addItem(.separator())
        let services = NSMenuItem(title: L("Dienste", "Services"), action: nil, keyEquivalent: ""); let sm = NSMenu(); services.submenu = sm; NSApp.servicesMenu = sm; app.addItem(services)
        app.addItem(.separator())
        add(app, L("RetroContacts ausblenden", "Hide RetroContacts"), #selector(NSApplication.hide(_:)), "h")
        add(app, L("Andere ausblenden", "Hide Others"), #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        add(app, L("Alle einblenden", "Show All"), #selector(NSApplication.unhideAllApplications(_:)))
        app.addItem(.separator())
        add(app, L("RetroContacts beenden", "Quit RetroContacts"), #selector(NSApplication.terminate(_:)), "q")

        let file = top(L("Ablage", "File"))
        add(file, L("Neue Karte", "New Card"), #selector(menuNew), "n")
        add(file, L("Neue Gruppe", "New Group"), #selector(menuNewGroup), "n", [.command, .shift])
        add(file, L("Neue intelligente Gruppe …", "New Smart Group…"), #selector(menuNewSmart), "n", [.command, .option])
        file.addItem(.separator())
        add(file, L("Aus Gruppe entfernen", "Remove from Group"), #selector(menuRemoveFromGroup))
        file.addItem(.separator())
        add(file, L("Als vCard importieren …", "Import vCard…"), #selector(menuImport), "o")
        add(file, L("Als vCard exportieren …", "Export vCard…"), #selector(menuExport), "e", [.command, .shift])
        file.addItem(.separator())
        add(file, L("Fenster schließen", "Close Window"), #selector(NSWindow.performClose(_:)), "w")
        add(file, L("Drucken …", "Print…"), #selector(menuPrint), "p")

        let edit = top(L("Bearbeiten", "Edit"))
        add(edit, L("Widerrufen", "Undo"), Selector(("undo:")), "z")
        add(edit, L("Wiederholen", "Redo"), Selector(("redo:")), "z", [.command, .shift])
        edit.addItem(.separator())
        add(edit, L("Ausschneiden", "Cut"), #selector(NSText.cut(_:)), "x")
        add(edit, L("Kopieren", "Copy"), #selector(NSText.copy(_:)), "c")
        add(edit, L("Einsetzen", "Paste"), #selector(NSText.paste(_:)), "v")
        add(edit, L("Alles auswählen", "Select All"), #selector(NSText.selectAll(_:)), "a")
        edit.addItem(.separator())
        add(edit, L("Karte bearbeiten / Fertig", "Edit Card / Done"), #selector(menuEdit), "l")
        add(edit, L("Karte löschen", "Delete Card"), #selector(menuDelete), String(UnicodeScalar(NSBackspaceCharacter)!))
        edit.addItem(.separator())
        add(edit, L("Suchen", "Find"), #selector(menuFind), "f")

        let view = top(L("Darstellung", "View"))
        for (i, t) in [L("Gruppen, Liste und Karte", "Groups, List and Card"), L("Liste und Karte", "List and Card"), L("Nur Karte", "Card Only")].enumerated() {
            let it = add(view, t, #selector(menuMode(_:)), "\(i + 1)"); it.tag = i
        }
        view.addItem(.separator())
        add(view, L("Vorherige Karte", "Previous Card"), #selector(menuPrev), String(UnicodeScalar(NSLeftArrowFunctionKey)!), [.command, .option])
        add(view, L("Nächste Karte", "Next Card"), #selector(menuNext), String(UnicodeScalar(NSRightArrowFunctionKey)!), [.command, .option])

        let win = top(L("Fenster", "Window")); NSApp.windowsMenu = win
        add(win, L("Im Dock ablegen", "Minimize"), #selector(menuMinimize), "m")
        add(win, L("Zoomen", "Zoom"), #selector(menuZoom))
        win.addItem(.separator())
        add(win, "RetroContacts", #selector(menuShowWindow), "0")
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
