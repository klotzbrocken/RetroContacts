# Apple compliance

RetroContacts is an **unofficial hobby project**, not affiliated with, endorsed or reviewed by Apple Inc.

## Technical

| Topic | Implementation |
|---|---|
| Signing | Developer ID Application, hardened runtime, secure timestamp (`build.sh`, `release.sh`) |
| Notarization | `notarytool` for the app **and** the DMG, then `stapler staple` (valid offline) |
| Contacts access | Public Contacts.framework API only; `NSContactsUsageDescription` (de/en); entitlement `com.apple.security.personal-information.addressbook`; access is requested at launch, the app stays usable without it |
| Notes | Apple requires the special entitlement `com.apple.developer.contacts.notes` for this. It is **not** requested: system notes are neither read nor overwritten. Notes are stored locally (`~/Library/Application Support/RetroContacts/notes.json`) |
| Private APIs | None. No access to the internal AddressBook database |
| Bundle stays unchanged | The custom 256×256 icon is only set at runtime as Dock icon (`NSApp.applicationIconImage`); the signed bundle is never written to (that would break the signature) |
| Privacy manifest | `PrivacyInfo.xcprivacy`: no tracking, no collected data, UserDefaults (CA92.1) |
| Export compliance | `ITSAppUsesNonExemptEncryption = false` |
| Network | No network access of its own; no logging of contact data |
| Font | *Lucida Grande* is only referenced from the system, not shipped; if missing, the app falls back to the system font |
| Mac App Store | Not planned (would need the sandbox and a separate review). Distribution: Developer ID + notarization |

## Legal (hints, not legal advice)

- **Name:** "RetroContacts" does not use an Apple trademark as a product name. Do not use "Contacts", "Kontakte", "Mac" or "OS X" as the app name.
- **Design:** the book/leather design is a homage to the OS X 10.8 interface. **No Apple image files, icons, textures or font files** are copied; everything is redrawn. Recreating the look may be seen as a trade-dress issue when distributed **publicly or commercially**.
- **Icon:** the supplied icon is AI-generated and not covered by the GPL (all rights reserved). Forks may use their own via the *App icon* setting (PNG 256 × 256).
- **Screenshots/references** (Ars Technica, Macworld, …) are local development references only and not part of the repository.
- "Mountain Lion" / "OS X" are used descriptively only.
