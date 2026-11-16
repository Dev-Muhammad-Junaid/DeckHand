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
| Loom SSH bootstrap (linked in, not used by Pixel Hand) | SwiftNIO SSH 0.15.1 | `swift-crypto` 4.5.1's `Crypto` module, which on Apple platforms is a thin re-export of CryptoKit. Its BoringSSL copy is only compiled for Linux, Windows, Android, WASI and OpenBSD. Re-checked for 4.5.1 in November 2026; see "Re-check after the Loom merge" below |
| CloudKit, Sentry uploads | HTTPS | Apple's OS networking (URLSession / CloudKit) |

So the encryption is for confidentiality of user data, which is more than the
"authentication only" exemption covers. But it's all standard, published
algorithms (NIST P-256, RFC 5869, RFC 8439), it's all done by code that ships
in Apple's operating system, and nothing proprietary or self-implemented is
bundled.

## Re-check after the Loom merge (November 2026)

The Loom 2.2.16 merge pins `swift-crypto` `exact: "4.5.1"` in core `Loom`
and resolves `swift-nio-ssh` to 0.15.1. The question was whether any
BoringSSL-backed code (swift-crypto's own C crypto, `_CryptoExtras`, or
anything swift-nio-ssh brings) now gets compiled into the iOS app.
**Answer: no, as far as the package manifests and sources show. The answer
`ITSAppUsesNonExemptEncryption = NO` stands.** What was checked, read from the
tagged sources (`apple/swift-crypto` 4.5.1, `apple/swift-nio-ssh` 0.15.1):

1. **What the app links.** Both apps depend on `LoomKit` only. `LoomKit` →
   `Loom` + `LoomCloudKit` + `LoomSharedRuntime`; `Loom` →
   `Crypto` (swift-crypto), `NIOCore`, `NIOPosix`, `NIOConcurrencyHelpers`,
   `NIOSSH`. Nothing in the graph names `_CryptoExtras` or `CryptoExtras`.
2. **swift-crypto 4.5.1 `Package.swift`.** The `Crypto` target's dependencies
   on `CCryptoBoringSSL`, `CCryptoBoringSSLShims`, `CryptoBoringWrapper`,
   `CXKCP` and `CXKCPShims` all carry
   `.when(platforms: [.linux, .android, .windows, .wasi, .openbsd])`, and the
   `CRYPTO_IN_SWIFTPM_FORCE_BUILD_API` define (which switches the Swift code
   to its BoringSSL implementation) has the same condition. On iOS and macOS
   the Swift sources take the `#if CRYPTO_IN_SWIFTPM && !CRYPTO_IN_SWIFTPM_FORCE_BUILD_API`
   branch, which is `@_exported import CryptoKit`. The newer algorithms in 4.x
   (ML-KEM, ML-DSA, X-Wing) are in `*_boring.swift` files on the same switch,
   so on Apple platforms they're CryptoKit's or absent.
3. **`_CryptoExtras` / `CryptoExtras` do bundle BoringSSL on every platform**
   (their BoringSSL dependencies are unconditional). That is why it matters
   that nothing links them: they'd put a second, non-OS implementation of
   standard crypto in the app.
4. **swift-nio-ssh 0.15.1** depends on `Crypto` only (the `NIOSSH` target:
   `NIOCore`, `NIOConcurrencyHelpers`, `NIOFoundationCompat`, `Crypto`,
   `Atomics`). No source file imports `_CryptoExtras`.
5. **Loom's own crypto** imports `CryptoKit` directly on Apple platforms
   (`#if canImport(CryptoKit) import CryptoKit #else import Crypto`) in
   `LoomSessionSecurity`, `LoomMediaSecurity`, `LoomIdentityManager`,
   `LoomTransferEngine` and the bootstrap/SSH files.
6. **Sentry** (`sentry-cocoa` 9.x) sends reports over `URLSession`; it ships
   no TLS or cipher implementation.

### Confirm on the Mac (needs a build)

This was a source reading, not a look at a binary. One check settles it.
Archive the iOS app (or build it for a device) and run:

```bash
APP="$(find ~/Library/Developer/Xcode/Archives -name 'Pixel Hand.app' -path '*Products/Applications*' | tail -1)"
nm -gU "$APP/Pixel Hand" 2>/dev/null | grep -ci 'CCryptoBoringSSL\|BORINGSSL\|_EVP_\|_SSL_CTX' ; \
  strings "$APP/Pixel Hand" | grep -ci 'boringssl'
find "$APP/Frameworks" -maxdepth 1 -print
```

Both counts should be `0`, and `Frameworks/` should hold no `CCryptoBoringSSL`
or `CryptoExtras` framework. If either count isn't zero, don't submit with
`NO`: stop and re-read "When this answer changes" below. One known way it could
happen: Xcode's SwiftPM integration has at times built conditional target
dependencies on every platform. The check above catches that.

### The Mac app (Developer ID download)

- `ITSAppUsesNonExemptEncryption` is an App Store Connect key. The Mac app
  isn't uploaded to App Store Connect (only to the notary service, which
  doesn't ask), so the key doesn't apply. It uses the same CryptoKit code as
  the iOS app.
- **Sparkle 2** adds an Ed25519 *signature check* of downloaded updates
  (Sparkle bundles its own small Ed25519 implementation) and downloads them
  over HTTPS through `URLSession`. Signature verification is
  authentication/integrity, which the export rules treat as exempt, and it
  isn't in the iOS app at all.
- The download is free and publicly available, standard cryptography,
  mass market (5D992.c). **Owner to confirm:** that Mega Creations LLC is a
  U.S. company exporting from the U.S. (this reading assumes so), and that no
  one is expected to download it from an embargoed country. Cloudflare will
  serve the DMG anywhere; restricting it isn't set up.

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
  In particular: anything starts depending on swift-crypto's `_CryptoExtras`
  or `CryptoExtras` (RSA, AES-CBC/CTR, ChaChaPoly-on-BoringSSL helpers and so
  on), swift-crypto stops conditioning BoringSSL to non-Apple platforms in a
  version bump, or `swift-nio-ssl` is added.
- Anything uses a non-standard or proprietary algorithm.
- The app is distributed in a way that leaves the App Store's coverage (e.g. a
  separately downloaded iOS build).

The Mac app isn't on the App Store, so `ITSAppUsesNonExemptEncryption` doesn't
apply to it; the same mass-market classification covers the Developer ID
download.
