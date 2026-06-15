#!/usr/bin/env bash
#
# push-secrets-from-1password.sh
#
# Reads every release secret from 1Password (op CLI) and pushes it to the
# GitHub repo's Actions secrets (gh CLI). One `op read` -> `gh secret set` line
# per secret. Run it after you have stored your signing artifacts in 1Password.
#
#   ./scripts/push-secrets-from-1password.sh                 # uses REPO below
#   ./scripts/push-secrets-from-1password.sh owner/repo      # override repo
#
# Prereqs:  brew install 1password-cli gh   &&   eval "$(op signin)"   &&   gh auth login
#
set -euo pipefail

REPO="${1:-mekedron/HiddenBarIcons}"

# ─── EDIT THESE to point at YOUR 1Password items/fields ──────────────────────
# Reference format: op://<vault>/<item>/<field>
# Discover yours with:  op item list      and    op item get "<item>" --format json
#
# This assumes the cert/key files are stored as base64 *fields*. If instead you
# saved the raw .p12 / .p8 as 1Password *documents*, use the document form shown
# in the commented lines further down.
OP_P12_BASE64="op://Private/HiddenBarIcons DevID/p12_base64"
OP_P12_PASSWORD="op://Private/HiddenBarIcons DevID/p12_password"
OP_NOTARY_KEY_ID="op://Private/HiddenBarIcons Notary/key_id"
OP_NOTARY_ISSUER_ID="op://Private/HiddenBarIcons Notary/issuer_id"
OP_NOTARY_P8_BASE64="op://Private/HiddenBarIcons Notary/p8_base64"
OP_SPARKLE_PRIVATE_KEY="op://Private/HiddenBarIcons Sparkle/private_key"
OP_HOMEBREW_TAP_TOKEN="op://Access Tokens And Keys/Github Homebrew Tap Repo Access Token/password"  # optional, e.g. op://Private/HiddenBarIcons Homebrew/token
# ─────────────────────────────────────────────────────────────────────────────

command -v op >/dev/null || { echo "1Password CLI not found: brew install 1password-cli"; exit 1; }
command -v gh >/dev/null || { echo "GitHub CLI not found: brew install gh"; exit 1; }
op account get >/dev/null 2>&1 || { echo "Sign in to 1Password first:  eval \"\$(op signin)\""; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Sign in to GitHub first:  gh auth login"; exit 1; }
echo "Target repo: $REPO"

# Read a value from 1Password and push it to GitHub (value never hits argv/disk).
push() {  # SECRET_NAME  op://reference
  local name="$1" ref="$2"
  if [ -z "$ref" ]; then echo "· skip $name (no reference set)"; return; fi
  op read "$ref" | gh secret set "$name" --repo "$REPO"
  echo "✓ set $name"
}

# One line per secret: read from 1Password, push to GitHub Actions secrets.
push MACOS_CERTIFICATE_P12_BASE64   "$OP_P12_BASE64"
push MACOS_CERTIFICATE_P12_PASSWORD "$OP_P12_PASSWORD"
push MACOS_NOTARY_KEY_ID            "$OP_NOTARY_KEY_ID"
push MACOS_NOTARY_ISSUER_ID         "$OP_NOTARY_ISSUER_ID"
push MACOS_NOTARY_KEY_P8_BASE64     "$OP_NOTARY_P8_BASE64"
push SPARKLE_PRIVATE_KEY            "$OP_SPARKLE_PRIVATE_KEY"
push HOMEBREW_TAP_TOKEN             "$OP_HOMEBREW_TAP_TOKEN"

# MACOS_KEYCHAIN_PASSWORD is just a throwaway used to unlock the CI keychain —
# generate a random one, no 1Password entry needed.
openssl rand -base64 24 | gh secret set MACOS_KEYCHAIN_PASSWORD --repo "$REPO"
echo "✓ set MACOS_KEYCHAIN_PASSWORD (random)"

echo
echo "Done. Verify with:  gh secret list --repo $REPO"

# ─── Alternative: secrets stored as 1Password DOCUMENTS (raw .p12 / .p8) ──────
# If you saved the certificate/key files as documents instead of base64 fields,
# replace the two base64 lines above with these (base64-encode on the fly):
#
#   op document get "HiddenBarIcons DevID p12" | base64 | gh secret set MACOS_CERTIFICATE_P12_BASE64 --repo "$REPO"
#   op document get "HiddenBarIcons Notary p8" | base64 | gh secret set MACOS_NOTARY_KEY_P8_BASE64   --repo "$REPO"
