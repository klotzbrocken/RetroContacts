import Cocoa
import Contacts

// MARK: - Localisation (de / en)

let isGerman = (Locale.preferredLanguages.first ?? "en").hasPrefix("de")
func L(_ de: String, _ en: String) -> String { isGerman ? de : en }

// MARK: - Value types

struct LabeledText: Equatable { var label: String; var value: String }   // label = CNLabel constant or custom text

struct PostalAddr: Equatable {
    var label: String
    var street = "", city = "", state = "", zip = "", country = ""
    var isEmpty: Bool { [street, city, state, zip, country].allSatisfy { $0.isEmpty } }
}

struct Person: Identifiable {
    var id: String
    var prefix = "", given = "", middle = "", family = "", suffix = "", nickname = ""
    var org = "", dept = "", job = ""
    var phones: [LabeledText] = []
    var emails: [LabeledText] = []
    var urls: [LabeledText] = []
    var addrs: [PostalAddr] = []
    var chats: [LabeledText] = []          // read-only passthrough (IM + social)
    var birthday: DateComponents?
    var photo: Data?
    var containerID = ""
    var cn: CNContact?                     // original system record (keeps untouched fields on save)
    var isNew = false
    var asCompany = false

    var isCompany: Bool { asCompany || (given.isEmpty && family.isEmpty && !org.isEmpty) }

    /// full name shown on the card
    var fullName: String {
        if isCompany { return org }
        let parts = [prefix, given, middle, family, suffix].filter { !$0.isEmpty }
        if !parts.isEmpty { return parts.joined(separator: " ") }
        if !nickname.isEmpty { return nickname }
        return org.isEmpty ? L("Kein Name", "No Name") : org
    }

    /// sorting key (stable, locale aware)
    func sortKey(byFamily: Bool) -> String {
        let a = byFamily ? [family, given] : [given, family]
        let k = (a + [org, nickname]).filter { !$0.isEmpty }.joined(separator: " ")
        return k.isEmpty ? "\u{10FFFF}" : k
    }

    func listTitle(displayFamilyFirst: Bool, boldFamily: Bool) -> NSAttributedString {
        let reg = Fonts.regular(12), bold = Fonts.bold(12)
        let out = NSMutableAttributedString()
        func add(_ s: String, _ f: NSFont) {
            if s.isEmpty { return }
            if out.length > 0 { out.append(NSAttributedString(string: displayFamilyFirst ? ", " : " ", attributes: [.font: reg])) }
            out.append(NSAttributedString(string: s, attributes: [.font: f]))
        }
        if given.isEmpty && family.isEmpty {
            add(org.isEmpty ? (nickname.isEmpty ? L("Kein Name", "No Name") : nickname) : org, bold)
        } else {
            let g = [given, middle].filter { !$0.isEmpty }.joined(separator: " ")
            let gf = boldFamily ? reg : bold, ff = boldFamily ? bold : reg
            if displayFamilyFirst { add(family, ff); add(g, gf) } else { add(g, gf); add(family, ff) }
        }
        return out
    }

    func matches(_ q: String) -> Bool {
        let hay = ([fullName, nickname, org] + phones.map { $0.value } + emails.map { $0.value }).joined(separator: "\n")
        let digits = hay.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return q.split(separator: " ").allSatisfy { digits.contains($0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)) }
    }
}

struct Group: Identifiable { var id: String; var name: String; var containerID: String; var members: Set<String> }
struct Container: Identifiable { var id: String; var name: String; var writable: Bool }

// MARK: - Smart groups (kept locally, rules re-evaluated live)

struct SmartRule: Codable, Equatable { var field: Int = 0; var op: Int = 0; var value: String = "" }
struct SmartGroup: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    var matchAll = true
    var rules: [SmartRule] = [SmartRule()]

    static let fields = [L("Name", "Name"), L("Firma", "Company"), L("Telefon", "Phone"), L("E-Mail", "Email"), L("Ort", "City"), L("Postleitzahl", "Zip Code")]
    static let ops = [L("enthält", "contains"), L("ist", "is"), L("beginnt mit", "starts with"), L("ist vorhanden", "is set")]

    func matches(_ p: Person) -> Bool {
        let results = rules.map { r -> Bool in
            let vals: [String]
            switch r.field {
            case 0: vals = [p.fullName]
            case 1: vals = [p.org]
            case 2: vals = p.phones.map { $0.value }
            case 3: vals = p.emails.map { $0.value }
            case 4: vals = p.addrs.map { $0.city }
            default: vals = p.addrs.map { $0.zip }
            }
            let v = r.value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            func f(_ s: String) -> String { s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) }
            switch r.op {
            case 0: return vals.contains { f($0).contains(v) }
            case 1: return vals.contains { f($0) == v }
            case 2: return vals.contains { f($0).hasPrefix(v) }
            default: return vals.contains { !$0.isEmpty }
            }
        }
        return matchAll ? results.allSatisfy { $0 } : results.contains(true)
    }
}

// MARK: - Store (system contacts via Contacts.framework, or synthetic demo data)

extension Notification.Name {
    static let storeChanged = Notification.Name("RCStoreChanged")
    static let prefsChanged = Notification.Name("RCPrefsChanged")
}

enum Access { case unknown, granted, denied }

final class Store {
    static let shared = Store()
    let cn = CNContactStore()
    var demo = false
    var access: Access = .unknown
    var people: [Person] = []
    var groups: [Group] = []
    var containers: [Container] = []
    var smartGroups: [SmartGroup] = [] { didSet { saveSmart() } }
    var notes: [String: String] = [:]
    var lastError: String?

    static let keys: [CNKeyDescriptor] = [
        CNContactIdentifierKey, CNContactNamePrefixKey, CNContactGivenNameKey, CNContactMiddleNameKey, CNContactFamilyNameKey,
        CNContactNameSuffixKey, CNContactNicknameKey, CNContactOrganizationNameKey, CNContactDepartmentNameKey, CNContactJobTitleKey,
        CNContactPhoneNumbersKey, CNContactEmailAddressesKey, CNContactUrlAddressesKey, CNContactPostalAddressesKey,
        CNContactInstantMessageAddressesKey, CNContactSocialProfilesKey, CNContactBirthdayKey,
        CNContactImageDataKey, CNContactImageDataAvailableKey, CNContactTypeKey,
        CNContactVCardSerialization.descriptorForRequiredKeys()
    ].map { $0 as! CNKeyDescriptor }

    private var supportDir: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("RetroContacts")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    init() {
        if let d = try? Data(contentsOf: supportDir.appendingPathComponent("smartgroups.json")),
           let s = try? JSONDecoder().decode([SmartGroup].self, from: d) { smartGroups = s }
        if let d = try? Data(contentsOf: supportDir.appendingPathComponent("notes.json")),
           let n = try? JSONDecoder().decode([String: String].self, from: d) { notes = n }
        NotificationCenter.default.addObserver(forName: .CNContactStoreDidChange, object: nil, queue: .main) { [weak self] _ in
            guard let self = self, !self.demo else { return }
            self.reload(); NotificationCenter.default.post(name: .storeChanged, object: nil)
        }
    }

    private func saveSmart() { try? JSONEncoder().encode(smartGroups).write(to: supportDir.appendingPathComponent("smartgroups.json"), options: .atomic) }
    func setNote(_ n: String, for id: String) {
        if n.isEmpty { notes[id] = nil } else { notes[id] = n }
        try? JSONEncoder().encode(notes).write(to: supportDir.appendingPathComponent("notes.json"), options: .atomic)
    }

    // MARK: access

    func requestAccess(_ done: @escaping () -> Void) {
        if demo { access = .granted; reload(); done(); return }
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized: access = .granted; reload(); done()
        case .notDetermined:
            cn.requestAccess(for: .contacts) { ok, _ in
                DispatchQueue.main.async { self.access = ok ? .granted : .denied; if ok { self.reload() }; done() }
            }
        default: access = .denied; done()
        }
    }

    func reload() {
        if demo { if people.isEmpty { loadDemo() }; return }
        guard access == .granted else { return }
        var ppl: [Person] = [], grs: [Group] = [], conts: [Container] = []
        do {
            for c in try cn.containers(matching: nil) {
                let name: String
                switch c.type {
                case .local: name = L("Auf meinem Mac", "On My Mac")
                case .cardDAV, .exchange:
                    name = c.name == "iCloud" || c.name.isEmpty ? "iCloud" : c.name
                default: name = c.name
                }
                conts.append(Container(id: c.identifier, name: name, writable: true))
                let req = CNContactFetchRequest(keysToFetch: Store.keys)
                req.predicate = CNContact.predicateForContactsInContainer(withIdentifier: c.identifier)
                req.unifyResults = false
                try cn.enumerateContacts(with: req) { c0, _ in var p = Person(cn: c0); p.containerID = c.identifier; ppl.append(p) }
                for g in try cn.groups(matching: CNGroup.predicateForGroupsInContainer(withIdentifier: c.identifier)) {
                    let mem = (try? cn.unifiedContacts(matching: CNContact.predicateForContactsInGroup(withIdentifier: g.identifier), keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor])) ?? []
                    grs.append(Group(id: g.identifier, name: g.name, containerID: c.identifier, members: Set(mem.map { $0.identifier })))
                }
            }
            lastError = nil
        } catch { lastError = error.localizedDescription }
        people = ppl; groups = grs; containers = conts
    }

    // MARK: mutation

    /// returns the stored contact's id, or nil when saving failed (lastError says why)
    func save(_ p: Person) -> String? {
        if demo {
            var p = p; p.isNew = false
            if let i = people.firstIndex(where: { $0.id == p.id }) { people[i] = p } else { people.append(p) }
            return p.id
        }
        let req = CNSaveRequest()
        let m: CNMutableContact
        if let orig = p.cn, !p.isNew { m = orig.mutableCopy() as! CNMutableContact } else { m = CNMutableContact() }
        p.apply(to: m)
        if p.isNew { req.add(m, toContainerWithIdentifier: p.containerID.isEmpty ? nil : p.containerID) } else { req.update(m) }
        do { try cn.execute(req); lastError = nil; return m.identifier } catch { lastError = error.localizedDescription; return nil }
    }

    func delete(_ p: Person) -> Bool {
        if demo { people.removeAll { $0.id == p.id }; return true }
        guard let orig = p.cn else { return false }
        let req = CNSaveRequest(); req.delete(orig.mutableCopy() as! CNMutableContact)
        do { try cn.execute(req); return true } catch { lastError = error.localizedDescription; return false }
    }

    func addGroup(named n: String, in containerID: String?) -> Bool {
        if demo { groups.append(Group(id: UUID().uuidString, name: n, containerID: containerID ?? "demo", members: [])); return true }
        let g = CNMutableGroup(); g.name = n
        let req = CNSaveRequest(); req.add(g, toContainerWithIdentifier: containerID)
        do { try cn.execute(req); reload(); return true } catch { lastError = error.localizedDescription; return false }
    }

    func renameGroup(_ g: Group, to n: String) {
        if demo { if let i = groups.firstIndex(where: { $0.id == g.id }) { groups[i].name = n }; return }
        guard let sys = try? cn.groups(matching: CNGroup.predicateForGroups(withIdentifiers: [g.id])).first else { return }
        let m = sys.mutableCopy() as! CNMutableGroup; m.name = n
        let req = CNSaveRequest(); req.update(m); try? cn.execute(req); reload()
    }

    func deleteGroup(_ g: Group) {      // only removes the group, never its members
        if demo { groups.removeAll { $0.id == g.id }; return }
        guard let sys = try? cn.groups(matching: CNGroup.predicateForGroups(withIdentifiers: [g.id])).first else { return }
        let req = CNSaveRequest(); req.delete(sys.mutableCopy() as! CNMutableGroup); try? cn.execute(req); reload()
    }

    func add(_ ids: [String], to g: Group) {
        if demo { if let i = groups.firstIndex(where: { $0.id == g.id }) { ids.forEach { groups[i].members.insert($0) } }; return }
        guard let sys = try? cn.groups(matching: CNGroup.predicateForGroups(withIdentifiers: [g.id])).first else { return }
        let req = CNSaveRequest()
        for id in ids where !g.members.contains(id) {
            if let p = people.first(where: { $0.id == id }), p.containerID == g.containerID, let c = p.cn { req.addMember(c, to: sys) }
        }
        try? cn.execute(req); reload()
    }

    func remove(_ ids: [String], from g: Group) {   // membership only
        if demo { if let i = groups.firstIndex(where: { $0.id == g.id }) { ids.forEach { groups[i].members.remove($0) } }; return }
        guard let sys = try? cn.groups(matching: CNGroup.predicateForGroups(withIdentifiers: [g.id])).first else { return }
        let req = CNSaveRequest()
        for id in ids { if let c = people.first(where: { $0.id == id })?.cn { req.removeMember(c, from: sys) } }
        try? cn.execute(req); reload()
    }

    func vcard(_ ps: [Person], photos: Bool = true) -> Data? {
        let cs: [CNContact] = ps.map { p in
            var p = p; if !photos { p.photo = nil }
            let m = (p.cn?.mutableCopy() as? CNMutableContact) ?? CNMutableContact(); p.apply(to: m)
            if !photos { m.imageData = nil }
            return m
        }
        return try? CNContactVCardSerialization.data(with: cs)
    }

    func importVCard(_ data: Data, into containerID: String?) -> Int {
        guard let cs = try? CNContactVCardSerialization.contacts(with: data) else { return 0 }
        if demo { cs.forEach { var p = Person(cn: $0); p.id = UUID().uuidString; people.append(p) }; return cs.count }
        let req = CNSaveRequest()
        cs.forEach { req.add($0.mutableCopy() as! CNMutableContact, toContainerWithIdentifier: containerID) }
        do { try cn.execute(req); reload(); return cs.count } catch { lastError = error.localizedDescription; return 0 }
    }
}

// MARK: - CNContact <-> Person

extension Person {
    init(cn c: CNContact) {
        self.init(id: c.identifier)
        cn = c
        prefix = c.namePrefix; given = c.givenName; middle = c.middleName; family = c.familyName; suffix = c.nameSuffix
        nickname = c.nickname; org = c.organizationName; dept = c.departmentName; job = c.jobTitle
        func lab(_ l: String?) -> String { l ?? CNLabelOther }
        phones = c.phoneNumbers.map { LabeledText(label: lab($0.label), value: $0.value.stringValue) }
        emails = c.emailAddresses.map { LabeledText(label: lab($0.label), value: $0.value as String) }
        urls = c.urlAddresses.map { LabeledText(label: lab($0.label), value: $0.value as String) }
        addrs = c.postalAddresses.map { PostalAddr(label: lab($0.label), street: $0.value.street, city: $0.value.city, state: $0.value.state, zip: $0.value.postalCode, country: $0.value.country) }
        chats = c.instantMessageAddresses.map { LabeledText(label: $0.value.service, value: $0.value.username) }
            + c.socialProfiles.map { LabeledText(label: $0.value.service, value: $0.value.username) }
        birthday = c.birthday
        photo = c.imageDataAvailable ? c.imageData : nil
        asCompany = c.contactType == .organization
    }

    func apply(to m: CNMutableContact) {
        m.namePrefix = prefix; m.givenName = given; m.middleName = middle; m.familyName = family; m.nameSuffix = suffix
        m.nickname = nickname; m.organizationName = org; m.departmentName = dept; m.jobTitle = job
        m.contactType = isCompany ? .organization : .person
        func lab(_ l: String) -> String? { l.isEmpty ? nil : l }
        m.phoneNumbers = phones.filter { !$0.value.isEmpty }.map { CNLabeledValue(label: lab($0.label), value: CNPhoneNumber(stringValue: $0.value)) }
        m.emailAddresses = emails.filter { !$0.value.isEmpty }.map { CNLabeledValue(label: lab($0.label), value: $0.value as NSString) }
        m.urlAddresses = urls.filter { !$0.value.isEmpty }.map { CNLabeledValue(label: lab($0.label), value: $0.value as NSString) }
        m.postalAddresses = addrs.filter { !$0.isEmpty }.map { a in
            let pa = CNMutablePostalAddress(); pa.street = a.street; pa.city = a.city; pa.state = a.state; pa.postalCode = a.zip; pa.country = a.country
            return CNLabeledValue(label: lab(a.label), value: pa as CNPostalAddress)
        }
        m.birthday = birthday
        m.imageData = photo
    }
}

// MARK: - Labels

enum Labels {
    static let phone = [CNLabelWork, CNLabelHome, CNLabelPhoneNumberMobile, CNLabelPhoneNumberMain, CNLabelPhoneNumberiPhone, CNLabelPhoneNumberHomeFax, CNLabelPhoneNumberWorkFax, CNLabelPhoneNumberPager, CNLabelOther]
    static let mail = [CNLabelWork, CNLabelHome, CNLabelOther]
    static let url = [CNLabelURLAddressHomePage, CNLabelHome, CNLabelWork, CNLabelOther]
    static let addr = [CNLabelWork, CNLabelHome, CNLabelOther]

    /// ML shows lower-case labels ("work", "home page")
    static func text(_ l: String) -> String {
        if l.hasPrefix("_$!<") { return CNLabeledValue<NSString>.localizedString(forLabel: l).lowercased() }
        return l
    }
}

// MARK: - Demo data (synthetic)

extension Store {
    func loadDemo() {
        containers = CommandLine.arguments.contains("--demo-multi") ? [Container(id: "icloud", name: "iCloud", writable: true), Container(id: "ldap", name: "Directories", writable: false)] : [Container(id: "icloud", name: "iCloud", writable: true)]
        func P(_ g: String, _ f: String, org: String = "", phone: String? = nil, mail: String? = nil, addr: PostalAddr? = nil, cont: String = "icloud") -> Person {
            var p = Person(id: UUID().uuidString); p.given = g; p.family = f; p.org = org; p.containerID = cont
            if let ph = phone { p.phones = [LabeledText(label: CNLabelWork, value: ph)] }
            if let m = mail { p.emails = [LabeledText(label: CNLabelWork, value: m)] }
            if let a = addr { p.addrs = [a] }
            return p
        }
        var list: [Person] = []
        let a = PostalAddr(label: CNLabelWork, street: "1-4-25, Kajino-cho", city: "Koganei-shi", state: "", zip: "184", country: "Japan")
        list.append(P("Shizuku", "Tsukishima", phone: "+81 5551810013", mail: "shizuku@ghibli.jp", addr: a))
        for (g, f) in [("Seiji", "Amasawa"), ("Seiya", "Tsukishima"), ("Shigeru", "Kayama"), ("Shigeru", "Muroi"), ("Shiho", "Kayama"), ("Shiro", "Kayama"), ("Takashi", "Tachibana"), ("Yorie", "Yamashita"), ("Youko", "Kayama"), ("Yuko", "Kayama"),
                       ("Alan", "Aaron"), ("Richard", "Aaron"), ("Henry", "Abelove"), ("Kay", "Achar"), ("Kate", "Adair"), ("James", "Adams"), ("Nicholas", "Adams"), ("Rachel", "Adams"), ("Steve", "Adelewitz"), ("Alana", "Adler"),
                       ("Colin", "Bannon"), ("Sarah", "Barbour"), ("Jeff", "Barone"), ("Jocie", "Bartlett"), ("Kristy", "Bohnet"), ("Gail", "Bonebrake"), ("Matt", "Boyd"), ("Fletcher", "Arnett"), ("Paton", "Ashbrook"),
                       ("Anna", "Müller"), ("Åsa", "Öberg"), ("Zoë", "Ünal")] {
            list.append(P(g, f, phone: "+49 30 5550\(Int.random(in: 100...999))", mail: "\(g.lowercased())@example.com"))
        }
        var apple = P("", "", org: "Apple Inc.", phone: "1 (800) MYAPPLE", mail: nil, addr: PostalAddr(label: CNLabelWork, street: "1 Infinite Loop", city: "Cupertino", state: "CA", zip: "95014", country: "United States"))
        apple.urls = [LabeledText(label: CNLabelURLAddressHomePage, value: "http://www.apple.com")]
        list.append(apple)
        list.append(P("Becky And Frank", "", org: "Becky And Frank"))
        list.append(P("", "", org: "Macworld Bloggers"))
        list.append(P("Holyoke", "", org: "Apple"))
        list.append(P("Stephen", "Hackett", mail: "stephen@hackett.fm"))
        list.append(P("", "", org: "Apple Computer Inc."))
        list.append(P("Max", "Mustermann", org: "RetroMac GmbH", phone: "+49 (0)30 1234567-89", mail: "max@retromac.example", cont: CommandLine.arguments.contains("--demo-multi") ? "ldap" : "icloud"))
        people = list
        groups = [Group(id: "g1", name: "Family", containerID: "icloud", members: Set(list.filter { $0.family == "Kayama" }.map { $0.id })),
                  Group(id: "g2", name: "Friends", containerID: "icloud", members: Set(list.filter { $0.family == "Adams" || $0.family == "Aaron" }.map { $0.id }))]
    }
}
