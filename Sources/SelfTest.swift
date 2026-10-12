import Cocoa
import Contacts

/// `RetroContacts --selftest` : headless checks of data handling, search, icon validation and performance.
/// Exit code 0 = all passed. Uses synthetic data only; never touches the real address book.
enum SelfTest {
    static var failures = 0
    static func check(_ ok: Bool, _ name: String) { print((ok ? "PASS  " : "FAIL  ") + name); if !ok { failures += 1 } }

    static func run() -> Int32 {
        let st = Store.shared; st.demo = true; st.access = .granted

        // --- vCard 3.0 round trip: unicode, single name, company, birthday without year, 29 Feb
        var a = Person(id: UUID().uuidString); a.given = "李"; a.family = "小龍"; a.emails = [LabeledText(label: CNLabelWork, value: "li@example.com")]
        a.phones = [LabeledText(label: CNLabelHome, value: "+49 (0)30 123456-78 ext. 5")]
        a.addrs = [PostalAddr(label: CNLabelWork, street: "Zeile 1\nHinterhof", city: "Köln", state: "", zip: "50667", country: "Deutschland")]
        a.birthday = DateComponents(month: 2, day: 29)
        var b = Person(id: UUID().uuidString); b.given = "Cher"
        var c = Person(id: UUID().uuidString); c.org = "Müller & Söhne 🚀"; c.asCompany = true
        var d = Person(id: UUID().uuidString); d.given = "Åsa"; d.family = "Öberg"; d.birthday = DateComponents(year: 1980, month: 12, day: 31)
        let data = st.vcard([a, b, c, d])
        check(data != nil && String(data: data!, encoding: .utf8)!.contains("BEGIN:VCARD"), "vCard export produces data")
        let back = (try? CNContactVCardSerialization.contacts(with: data ?? Data())) ?? []
        check(back.count == 4, "vCard re-import keeps 4 cards")
        let pa = back.first.map { Person(cn: $0) }
        check(pa?.given == "李" && pa?.family == "小龍", "vCard keeps non-latin names")
        check(pa?.phones.first?.value == "+49 (0)30 123456-78 ext. 5", "phone number raw value not stripped")
        check(pa?.addrs.first?.street.contains("Hinterhof") == true, "multi-line address survives")
        check(pa?.birthday?.month == 2 && pa?.birthday?.day == 29, "29 Feb birthday survives")
        check(back.count == 4 && Person(cn: back[3]).birthday?.year == 1980, "birthday with year survives")
        check(back.count == 4 && Person(cn: back[1]).given == "Cher" && Person(cn: back[1]).family.isEmpty, "single-name card")
        check(back.count == 4 && Person(cn: back[2]).org.hasPrefix("Müller") && Person(cn: back[2]).isCompany, "company-only card")
        let noPhoto = st.vcard([a], photos: false).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        check(!noPhoto.contains("PHOTO"), "export without photos has no PHOTO")

        // --- demo store CRUD, groups: remove from group never deletes the card
        st.people = []; st.groups = []; st.loadDemo()
        let n0 = st.people.count
        var np = Person(id: UUID().uuidString); np.given = "Test"; np.family = "Person"; np.isNew = true; np.containerID = "icloud"
        let id = st.save(np)
        check(id != nil && st.people.count == n0 + 1, "create card")
        var edited = st.people.first { $0.id == id }!; edited.org = "ACME"; edited.phones = [LabeledText(label: CNLabelWork, value: "0123")]
        _ = st.save(edited)
        check(st.people.first { $0.id == id }?.org == "ACME", "edit card")
        let g = st.groups[0]
        st.add([id!], to: g); check(st.groups[0].members.contains(id!), "add to group (no copy)")
        check(st.people.filter { $0.id == id }.count == 1, "no duplicate on group add")
        st.remove([id!], from: st.groups[0]); check(!st.groups[0].members.contains(id!) && st.people.contains { $0.id == id }, "remove from group keeps card")
        st.add([id!], to: st.groups[0]); st.deleteGroup(st.groups[0])
        check(st.people.contains { $0.id == id }, "deleting a group keeps its members")
        check(st.delete(st.people.first { $0.id == id }!) && !st.people.contains { $0.id == id }, "delete card")

        // --- smart groups
        var p = Person(id: "x"); p.given = "Zoë"; p.family = "Ünal"; p.org = "ACME"; p.emails = [LabeledText(label: "", value: "zoe@acme.test")]
        p.addrs = [PostalAddr(label: "", city: "Berlin", zip: "10115")]
        func sg(_ all: Bool, _ r: [SmartRule]) -> SmartGroup { SmartGroup(name: "t", matchAll: all, rules: r) }
        check(sg(true, [SmartRule(field: 0, op: 0, value: "unal")]).matches(p), "smart: name contains, diacritics tolerant")
        check(sg(true, [SmartRule(field: 1, op: 1, value: "acme"), SmartRule(field: 4, op: 2, value: "ber")]).matches(p), "smart: all rules")
        check(!sg(true, [SmartRule(field: 1, op: 1, value: "acme"), SmartRule(field: 5, op: 1, value: "99999")]).matches(p), "smart: all rules fail")
        check(sg(false, [SmartRule(field: 5, op: 1, value: "99999"), SmartRule(field: 3, op: 3, value: "")]).matches(p), "smart: any rule")

        // --- search: names, company, phone, email; no notes
        check(p.matches("zoe") && p.matches("ünal acme") && p.matches("ACME.TEST") && !p.matches("berlin"), "search scope and tolerance")

        // --- sorting sections keep non-latin and nameless cards
        let list = ContactList(frame: NSRect(x: 0, y: 0, width: 200, height: 300))
        var jp = Person(id: "jp"); jp.given = "太郎"; jp.family = "山田"
        var none = Person(id: "none"); none.phones = [LabeledText(label: "", value: "1")]
        list.setPeople([p, jp, none])
        check(list.rows.filter { if case .person = $0 { return true } else { return false } }.count == 3, "no card disappears in list")

        // --- performance: 10 000 contacts
        var big: [Person] = []
        for i in 0..<10_000 { var q = Person(id: "\(i)"); q.given = "Vorname\(i)"; q.family = "Nachname\(i % 977)"; q.emails = [LabeledText(label: "", value: "u\(i)@example.com")]; big.append(q) }
        var times: [Double] = []
        for k in 0..<20 { let t = Date(); _ = big.filter { $0.matches("nachname\(k)") }; times.append(Date().timeIntervalSince(t)) }
        times.sort(); let p95 = times[Int(Double(times.count) * 0.95) - 1]
        check(p95 < 0.2, String(format: "search 10 000 contacts p95 %.0f ms (< 200)", p95 * 1000))
        let t0 = Date(); list.setPeople(big); let tl = Date().timeIntervalSince(t0)
        check(tl < 1.5, String(format: "list build 10 000 contacts %.0f ms", tl * 1000))

        // --- app icon validation (256x256 PNG only)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("rc-icontest-\(UUID().uuidString)"); try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        func png(_ px: Int, _ name: String) -> URL {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let u = tmp.appendingPathComponent(name); try? rep.representation(using: .png, properties: [:])!.write(to: u); return u
        }
        let had = AppIcon.custom != nil
        let backup = had ? try? Data(contentsOf: AppIcon.file) : nil
        check(AppIcon.install(png(128, "a.png")) != nil, "icon: 128x128 PNG rejected")
        check(AppIcon.install(png(512, "b.png")) != nil, "icon: 512x512 PNG rejected")
        let jpg = tmp.appendingPathComponent("c.png"); try? Data([0xFF, 0xD8, 0xFF, 0xE0]).write(to: jpg)
        check(AppIcon.install(jpg) != nil, "icon: non-PNG content rejected")
        check(AppIcon.install(png(256, "d.png")) == nil && AppIcon.custom?.size != nil, "icon: 256x256 PNG accepted")
        if let b = backup { try? b.write(to: AppIcon.file) } else { AppIcon.reset() }
        try? FileManager.default.removeItem(at: tmp)

        // --- window geometry: minimum sizes are enforced and sane
        for m in [ViewMode.three, .two, .one] { check(m.minSize.width >= 340 && m.minSize.height >= 340 && m.defaultSize.width >= m.minSize.width && m.defaultSize.height >= m.minSize.height, "min size < default for mode \(m)") }
        let win = BookWindow(contentRect: NSRect(x: 0, y: 0, width: 906, height: 516), styleMask: [.miniaturizable, .closable], backing: .buffered, defer: false)
        win.minSize = ViewMode.three.minSize
        win.setFrame(NSRect(x: 0, y: 0, width: 50, height: 50), display: false)
        check(win.frame.width == ViewMode.three.minSize.width && win.frame.height == ViewMode.three.minSize.height, "tiny setFrame is clamped to minimum (\(win.frame.size))")
        check(win.minSize == ViewMode.three.minSize, "window minSize applied (\(win.minSize))")

        print(failures == 0 ? "ALL TESTS PASSED" : "\(failures) FAILED")
        return failures == 0 ? 0 : 1
    }
}
