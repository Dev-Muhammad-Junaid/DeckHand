# Export compliance (encryption)

Status: recommendation for the owner. This is a reading of Apple's and the
U.S. Bureau of Industry and Security (BIS) guidance, not legal advice. If you
want certainty, an export-control lawyer can confirm it in an hour.

## What the app actually does

| Where | What | Implemented by |
| --- | --- | --- |
| Loom session security (`Sources/Loom/Internal/Security/LoomSessionSecurity.swift`) | P-256 ECDH key agreement, HKDF-SHA256, ChaCha20-Poly1305 for every control message | Apple CryptoKit |
| Loom media security (`LoomMediaSecurity.swift`) | ChaCha20-Poly1305 for mirror frames and screenshots | Apple CryptoKit |
| Loom identity and trust | P-256 ECDSA signatures, SHA-256 | Apple CryptoKit, Keychain |
| Loom SSH bootstrap (linked in, not used by Pixel Hand) | SwiftNIO SSH | `swift-crypto`, which on Apple platforms is a thin re-export of CryptoKit. Its BoringSSL copy is only compiled for Linux, Windows, Android, WASI and OpenBSD (checked in swift-crypto 3.15.1's `Package.swift`) |
| CloudKit, Sentry uploads | HTTPS | Apple's OS networking (URLSession / CloudKit) |

So the encryption is for confidentiality of user data, which is more than the
"authentication only" exemption covers. But it's all standard, published
algorithms (NIST P-256, RFC 5869, RFC 8439), it's all done by code that ships
in Apple's operating system, and nothing proprietary or self-implemented is
bundled.

## How that maps onto Apple's questions

Apple's App Store Connect help says you must provide documentation only if the
app contains proprietary or non-standard algorithms, or "standard encryption
algorithms instead of, or in addition to, using or accessing the encryption
within Apple's operating system". Encryption limited to what's in Apple's OS
needs no documentation, and the French declaration is only for standard
algorithms *not* provided by the OS.

Pixel Hand only accesses the OS's encryption (CryptoKit). So:

- **`ITSAppUsesNonExemptEncryption` = `NO`** in `DeckHandiOS/Info.plist`
  (already set). App Store Connect then stops asking on every build.
- If App Store Connect asks anyway (it sometimes does when it sees CryptoKit
  linked), answer:
  - *Does your app use encryption?* → **Yes**
  - *What type of encryption algorithms does your app implement?* →
    **None of the algorithms mentioned above** (the app only uses or accesses
    the encryption in Apple's operating system).
  - No documentation, no French declaration.

Under U.S. export rules the app is a mass-market item (ECCN 5D992.c). Since
BIS's March 2021 rule, mass-market items with standard cryptography don't need
the annual self-classification report, so there is nothing to file with BIS
either.

## When this answer changes

Revisit this, and probably switch the key to `YES`, if any of these happen:

- Loom (or a dependency) starts bundling its own crypto implementation, e.g.
  BoringSSL/OpenSSL, libsodium, or a hand-written cipher.
- Anything uses a non-standard or proprietary algorithm.
- The app is distributed in a way that leaves the App Store's coverage (e.g. a
  separately downloaded iOS build).

The Mac app isn't on the App Store, so `ITSAppUsesNonExemptEncryption` doesn't
apply to it; the same mass-market classification covers the Developer ID
download.
