# RetroContacts

Kontakte-App im Stil des aufgeschlagenen, ledergebundenen Adressbuchs von OS X 10.8 – mit den **echten Systemkontakten** (Contacts.framework), für macOS 14+ (Apple Silicon & Intel).

* Drei Ansichten: Gruppen·Liste·Karte (⌘1), Liste·Karte (⌘2), nur Karte (⌘3, Blättern unten rechts)
* Anzeigen, Anlegen, Bearbeiten, Löschen; Suche (Name, Firma, Telefon, E-Mail); Gruppen & intelligente Gruppen; Drag & Drop in Gruppen
* vCard-Import/-Export, Teilen, Drucken
* Einstellungen (⌘,): Sortierung/Anzeige und **eigenes Programmsymbol (PNG, exakt 256 × 256 px)**
* Fenster haben Mindestgrößen (3 Spalten 680×420, 2 Spalten 520×380, Karte 370×340)

## Bauen & Testen
```bash
./build.sh                                   # universal, ad-hoc signiert
./RetroContacts.app/Contents/MacOS/RetroContacts --selftest   # 34 automatische Prüfungen
./RetroContacts.app/Contents/MacOS/RetroContacts --demo       # synthetische Demo-Daten
./release.sh                                 # Developer-ID-Signatur, Notarisierung, DMG (Keychain-Profil „Retromac“)
```
Siehe [COMPLIANCE.md](COMPLIANCE.md) für Apple-Richtlinien, Datenschutz und rechtliche Hinweise.
Inoffizielles Projekt, nicht mit Apple verbunden. Lizenz: MIT (ohne Icon-Artwork).
