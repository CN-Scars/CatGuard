# Code Signing & TCC (Accessibility Permission)

> The single biggest source of "it worked, now it doesn't" during CatGuard dev.

---

## Gotcha: ad-hoc signing invalidates TCC authorization on every rebuild

**Symptom**: You grant Accessibility permission, the app works. You rebuild (even with
zero code change to the permission path), relaunch — and the app behaves as if never
authorized (`AXIsProcessTrusted()` returns `false`, Lock button greys out).

**Cause**: macOS TCC binds Accessibility authorization to the app's **code signature
hash**. Xcode's default ad-hoc signing (`Signature=adhoc`, `TeamIdentifier=not set`)
produces a *different hash on every build*, so TCC treats each rebuild as a brand-new,
unauthorized app.

**Fix**: Use a **stable local self-signed code-signing identity** so the hash is stable
across rebuilds.

### Convention: create and use a local signing identity

```bash
# 1. Generate a self-signed code-signing cert (codeSigning EKU is required)
openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 3650 -nodes \
  -config cert.conf   # cert.conf must set extendedKeyUsage = critical,codeSigning

# 2. Package as PKCS#12 — MUST use a password + SHA1 MAC, or macOS `security` rejects it
openssl pkcs12 -export -inkey key.pem -in cert.pem -out id.p12 -name "CatGuard Local Dev" \
  -passout pass:catguard -macalg sha1 -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES

# 3. Import into login keychain
security import id.p12 -k ~/Library/Keychains/login.keychain-db -P catguard -T /usr/bin/codesign -A

# 4. Mark as trusted code-signing root (prompts for login password) — REQUIRED,
#    otherwise `security find-identity -v -p codesigning` shows 0 valid identities
security add-trusted-cert -r trustRoot -p codeSign -k ~/Library/Keychains/login.keychain-db cert.pem
```

Then in `project.yml`:

```yaml
settings:
  base:
    CODE_SIGN_STYLE: Manual
    CODE_SIGN_IDENTITY: "CatGuard Local Dev"
```

### Validation & Error Matrix

| Condition | Symptom | Resolution |
|-----------|---------|------------|
| `openssl pkcs12` with empty password | `MAC verification failed during PKCS12 import` | Use a non-empty password |
| OpenSSL 3.x default algorithms | same import failure on macOS LibreSSL | Force `-macalg sha1 -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES` (`-legacy` is unavailable in macOS LibreSSL) |
| cert imported but not trusted | `find-identity -p codesigning` → 0 valid | run `security add-trusted-cert -r trustRoot -p codeSign` |
| changed signing identity | TCC auth lost once more | Re-authorize one final time; stable thereafter |

> **Note**: Switching from ad-hoc → local identity changes the hash *once*, so a single
> final re-authorization is still needed. After that, rebuilds preserve authorization.

---

## Gotcha: Xcode 16 Debug Dylib breaks custom signing identity

**Symptom**: App built with a custom identity crashes immediately on launch:

```
dyld: Library not loaded: @rpath/CatGuard.debug.dylib
Reason: ... different Team IDs
```

**Cause**: Xcode 16+ splits Debug builds into a separate `CatGuard.debug.dylib`. The main
executable is signed with your identity, but the dylib's Team ID does not match, so dyld
refuses to load it.

**Fix**: disable the Debug Dylib split in `project.yml`:

```yaml
targets:
  CatGuard:
    settings:
      base:
        ENABLE_DEBUG_DYLIB: false
```

---

## Gotcha: unit-test bundle fails to load under hardened runtime + custom identity

**Symptom**: `xcodebuild test` fails with
`The bundle "CatGuardTests" couldn't be loaded ... different Team IDs`.

**Cause**: A test bundle hosted in the app (`TEST_HOST`) is injected into the
hardened-runtime, custom-signed app, and the Team IDs don't match.

**Fix**: For **pure-logic tests**, do not host them in the app. Compile the tested source
files directly into the test target (no `TEST_HOST`, no `@testable import`). See
[build-and-test.md](./build-and-test.md).
