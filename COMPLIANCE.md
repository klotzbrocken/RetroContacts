# Apple-Konformität / Apple compliance

RetroContacts ist ein **inoffizielles Hobbyprojekt**, nicht mit Apple Inc. verbunden, nicht von Apple geprüft oder gebilligt.
*RetroContacts is an unofficial hobby project, not affiliated with, endorsed or reviewed by Apple Inc.*

## Technisch (erledigt)
| Thema | Umsetzung |
|---|---|
| Signatur | Developer ID Application, Hardened Runtime, sicherer Zeitstempel (`build.sh`, `release.sh`) |
| Notarisierung | `notarytool` für App **und** DMG, anschließend `stapler staple` (offline gültig) |
| Kontakte-Zugriff | Nur öffentliche Contacts.framework-API; `NSContactsUsageDescription` (de/en); Entitlement `com.apple.security.personal-information.addressbook`; Zugriff wird erst beim Start abgefragt, ohne Zugriff bleibt die App bedienbar |
| Notizen | Apple verlangt dafür das Sonderentitlement `com.apple.developer.contacts.notes`. Es wird **nicht** angefragt: Systemnotizen werden weder gelesen noch überschrieben. Notizen liegen lokal (`~/Library/Application Support/RetroContacts/notes.json`) |
| Private APIs | Keine. Kein Zugriff auf die interne AddressBook-Datenbank |
| Bundle bleibt unverändert | Das eigene 256×256-Icon wird nur zur Laufzeit als Dock-Icon gesetzt (`NSApp.applicationIconImage`), das signierte Bundle wird nie beschrieben (sonst bräche die Signatur) |
| Privacy Manifest | `PrivacyInfo.xcprivacy`: kein Tracking, keine gesammelten Daten, UserDefaults (CA92.1) |
| Export Compliance | `ITSAppUsesNonExemptEncryption = false` |
| Netzwerk | Keine eigenen Netzwerkzugriffe; kein Logging von Kontaktdaten |
| Schrift | *Lucida Grande* wird nur vom System referenziert, nicht mitgeliefert; fehlt sie, fällt die App auf die Systemschrift zurück |
| Mac App Store | Nicht vorgesehen (wäre Sandbox + eigene Prüfung nötig). Verteilung: Developer ID + Notarisierung |

## Rechtlich (Hinweise, keine Rechtsberatung)
* **Name:** „RetroContacts“ enthält keine Apple-Marke als Produktname. Nicht „Contacts“, „Kontakte“, „Mac“ oder „OS X“ im App-Namen verwenden.
* **Gestaltung:** Das Buch-/Leder-Design ist eine Hommage an die Oberfläche von OS X 10.8. Es werden **keine Apple-Bilddateien, Icons, Texturen oder Schriftdateien** übernommen; alles ist neu gezeichnet. Eine Nachbildung des „Look“ kann bei **öffentlicher oder kommerzieller** Verbreitung als Trade-Dress-Thema gesehen werden – für private Nutzung und ein privates Repository ist das Risiko gering.
* **Icon:** Das gelieferte (KI-generierte) Icon ähnelt stark dem früheren Apple-Kontakte-Symbol. Vor einer öffentlichen Veröffentlichung ein eigenständiges Icon verwenden.
* **Screenshots/Referenzen** (Ars Technica, Macworld u. a.) sind nur lokale Entwicklungsreferenz und nicht Bestandteil des Repositorys.
* „Mountain Lion“ / „OS X“ werden ausschließlich beschreibend genannt.
