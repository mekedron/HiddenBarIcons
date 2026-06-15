# Release setup — from a fresh Apple Developer account to your first release

This is the prerequisite to running the secret-provisioning scripts. It walks you,
in order, through producing every artifact the release workflow
(`.github/workflows/release.yml`) needs.

You only need to do this once per machine. There are two ways to load the secrets
into GitHub once you have the artifacts:

- **`scripts/push-secrets-from-1password.sh`** — if you keep the artifacts in
  1Password. Edit the `op://` references at the top, then run it.
- **`scripts/bootstrap-release-secrets.sh`** — interactive; reads files/IDs from
  disk and pushes them with `gh`. It can also generate the Sparkle key.

---

## Before you start

- A paid **Apple Developer Program** membership ($99/yr). The free tier cannot
  issue a Developer ID Application certificate.
- macOS with **Keychain Access** (built-in).
- [GitHub CLI](https://cli.github.com) authenticated: `brew install gh && gh auth login`.
- Push access to `mekedron/HiddenBarIcons` — confirm with `gh auth status`.

## What you'll collect — a checklist

Keep these in one safe folder (suggested `~/HiddenBarIcons-release-keys/`, **not**
cloud-synced):

- [ ] **Developer ID Application `.p12`** — cert+key bundle that signs the app.
- [ ] **`.p12` export passphrase**.
- [ ] **Issuer ID** — App Store Connect API issuer UUID.
- [ ] **Key ID** — App Store Connect API key ID.
- [ ] **`.p8` file** — the App Store Connect API private key (**downloadable once**).
- [ ] **Sparkle Ed25519 private key** — you already have one (its public key is
      pinned in `Info.plist` as `SUPublicEDKey`); just have the private key ready.
- [ ] **Homebrew Tap PAT** — *optional*.

> [!IMPORTANT]
> The `.p8` (Section 2) is downloadable **exactly once**. Read Section 2 before
> clicking *Generate*.

---

## 1. Developer ID Application certificate (.p12)

### 1.1 Create a CSR
1. **Keychain Access → Certificate Assistant → Request a Certificate From a
   Certificate Authority…**
2. Enter your Apple ID email + a Common Name (e.g. `HiddenBarIcons CI`), select
   **Saved to disk**, tick **Let me specify key pair information**, **Continue**.
3. Keep defaults (2048-bit RSA), save the `.certSigningRequest`. Keychain stores the
   matching private key in your login keychain — don't delete it.

### 1.2 Request the certificate
1. <https://developer.apple.com/account/resources/certificates/list> → **+**.
2. **Software → Developer ID Application → Continue** (choose **G2 Sub-CA** if asked).
3. Upload the CSR, **Continue**, **Download** (`developerID_application.cer`).

### 1.3 Install + export
1. Double-click the `.cer` to add it to the **login** keychain.
2. In **My Certificates**, confirm `Developer ID Application: <Name> (TEAMID)` has a
   private key child. Right-click it → **Export…** → **Personal Information Exchange
   (.p12)** → set an **export passphrase** (write it down).

The workflow base64-decodes the `.p12` on the runner, imports it into a throwaway
keychain, and codesigns the app (and Sparkle's nested helpers) with hardened runtime.

✅ Have: `developer-id.p12` path, and its passphrase.

---

## 2. App Store Connect API key (notarization)

Apple authenticates notarization with an **App Store Connect API key**.

### 2.1–2.3
1. <https://appstoreconnect.apple.com> → **Users and Access → Integrations → Team Keys**.
2. Copy the **Issuer ID** shown at the top.
3. **Generate API Key**, name it (e.g. `HiddenBarIcons CI Notary`), access **Developer**,
   **Generate**. Note the **Key ID**.

> [!WARNING]
> **Download API Key works exactly once.** Lose it and you must revoke + recreate.

### 2.4 Download the .p8
1. **Download API Key** → `AuthKey_<KEYID>.p8`. Move it to your safe folder,
   `chmod 600`, back it up to your password manager.

The workflow base64-decodes the `.p8` and runs
`xcrun notarytool submit … --key … --key-id … --issuer …` for the `.app` and `.dmg`.

✅ Have: Issuer ID, Key ID, `AuthKey_<KEYID>.p8` path.

---

## 3. Sparkle EdDSA keypair

Sparkle verifies update downloads with an Ed25519 signature: a **private** key the
workflow signs DMGs with, and a **public** key embedded in
`HiddenBarIcons/Resources/Info.plist` as `SUPublicEDKey`.

This repo already ships a `SUPublicEDKey`. You must provide the **matching private
key** as the `SPARKLE_PRIVATE_KEY` secret (base64 of the 32-byte seed):

- **1Password flow:** point `OP_SPARKLE_PRIVATE_KEY` at the item holding it.
- **Bootstrap flow:** when prompted, give the path to your private key file. The
  script verifies it matches `SUPublicEDKey` and warns on mismatch. If you leave the
  path blank it generates a *new* keypair and rewrites `SUPublicEDKey` (only do this
  if no one runs a build signed with the old key yet — then rebuild & re-release).

> [!IMPORTANT]
> `SUPublicEDKey` and `SPARKLE_PRIVATE_KEY` must be a matching pair, or installed
> apps reject updates. The private key is unrecoverable — back it up.

✅ Have: the Sparkle private key (matching the pinned public key).

---

## 4. Homebrew Tap PAT (optional)

Lets the workflow auto-update a `hiddenbaricons` cask in your tap (e.g.
`mekedron/homebrew-tap`). Skip if you don't have a tap — the step becomes a no-op.

1. Create the tap repo with a `Casks/` dir.
2. <https://github.com/settings/tokens?type=beta> → **Generate new token**, scope to
   the tap repo, **Contents: Read and write**. Copy the token.

`HOMEBREW_TAP_TOKEN` is consumed by the **Update Homebrew Cask** step.

---

## Run it

```sh
# Option A — from 1Password (edit the op:// refs at the top first):
./scripts/push-secrets-from-1password.sh

# Option B — interactive, from files:
./scripts/bootstrap-release-secrets.sh           # or --skip-homebrew
```

Then trigger a release:

```sh
git tag v0.1.0 && git push origin v0.1.0
```

---

## Reference: secret names ↔ artifact mapping

| GitHub secret | What you provide |
|---|---|
| `MACOS_CERTIFICATE_P12_BASE64` | Developer ID Application `.p12` (base64) |
| `MACOS_CERTIFICATE_P12_PASSWORD` | `.p12` export passphrase |
| `MACOS_KEYCHAIN_PASSWORD` | (auto-generated random) |
| `MACOS_NOTARY_ISSUER_ID` | App Store Connect Issuer ID |
| `MACOS_NOTARY_KEY_ID` | App Store Connect Key ID |
| `MACOS_NOTARY_KEY_P8_BASE64` | `.p8` file (base64) |
| `SPARKLE_PRIVATE_KEY` | Sparkle private key (base64 32-byte seed) |
| `HOMEBREW_TAP_TOKEN` | Homebrew tap PAT (optional) |
