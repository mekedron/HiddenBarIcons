#!/usr/bin/env bash
# bootstrap-release-secrets.sh
#
# Walks you through generating + uploading every GitHub Actions secret the
# HiddenBarIcons release workflow (.github/workflows/release.yml) needs.
#
# Run once from the repo root after you have followed docs/release-setup.md
# and collected the Apple Developer artifacts (certificate .p12, App Store
# Connect .p8 + IDs, and optional Homebrew PAT). Re-running is safe — it
# replaces existing secrets in place without leaving orphans.
#
# Usage:
#   ./scripts/bootstrap-release-secrets.sh             # interactive
#   ./scripts/bootstrap-release-secrets.sh --skip-homebrew
#   ./scripts/bootstrap-release-secrets.sh --help

set -euo pipefail

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
SKIP_HOMEBREW_FLAG=0
for arg in "$@"; do
    case "$arg" in
        --skip-homebrew) SKIP_HOMEBREW_FLAG=1 ;;
        -h|--help)
            sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            echo "Run with --help for usage." >&2
            exit 2
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Pretty output helpers
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
    BOLD=$(tput bold || true); DIM=$(tput dim || true); RED=$(tput setaf 1 || true)
    GREEN=$(tput setaf 2 || true); YELLOW=$(tput setaf 3 || true); BLUE=$(tput setaf 4 || true)
    RESET=$(tput sgr0 || true)
else
    BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; RESET=""
fi
say()    { printf '%s\n' "${BLUE}==>${RESET} $*"; }
ok()     { printf '%s\n' "${GREEN}✓${RESET} $*"; }
warn()   { printf '%s\n' "${YELLOW}⚠${RESET}  $*" >&2; }
fail()   { printf '%s\n' "${RED}✗${RESET} $*" >&2; exit 1; }
header() { printf '\n%s\n' "${BOLD}$*${RESET}"; }

# ---------------------------------------------------------------------------
# Temp scratch dir — every plaintext secret goes here and is wiped on exit
# ---------------------------------------------------------------------------
TMPDIR=$(mktemp -d -t hiddenbaricons-bootstrap.XXXXXX)
chmod 700 "$TMPDIR"
cleanup() {
    local code=$?
    if [ -d "$TMPDIR" ]; then
        find "$TMPDIR" -type f -exec rm -f {} +
        rmdir "$TMPDIR" 2>/dev/null || rm -rf "$TMPDIR"
    fi
    [ "$code" -ne 0 ] && warn "Aborted (exit ${code}). No state left in ${TMPDIR}."
}
trap cleanup EXIT INT TERM

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
header "Pre-flight checks"
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
[ -z "$REPO_ROOT" ] && fail "Not inside a git working tree. cd into the HiddenBarIcons repo and re-run."
cd "$REPO_ROOT"
ok "Repo root: ${REPO_ROOT}"

command -v gh >/dev/null 2>&1 || fail "GitHub CLI (\`gh\`) not found. Install: brew install gh"
ok "gh CLI present ($(gh --version | head -1))"
gh auth status >/dev/null 2>&1 || fail "gh is not authenticated. Run \`gh auth login\` first."
ok "gh authenticated"

REMOTE_URL=$(git remote get-url origin 2>/dev/null || true)
[ -z "$REMOTE_URL" ] && fail "No 'origin' git remote set. Add it before running this script."
REPO_SLUG=$(echo "$REMOTE_URL" \
    | sed -E 's#(git@github.com:|https://github.com/)##' \
    | sed -E 's#\.git$##')
if [ -z "$REPO_SLUG" ] || [ "$REPO_SLUG" = "$REMOTE_URL" ]; then
    fail "Could not parse a GitHub owner/repo from origin URL: ${REMOTE_URL}"
fi
ok "Target repo: ${REPO_SLUG}"
gh secret list --repo "$REPO_SLUG" >/dev/null 2>&1 \
    || fail "gh cannot list secrets on ${REPO_SLUG}. Check that your gh login has access."
ok "gh has access to repo secrets"

# ---------------------------------------------------------------------------
# Summary tracking + push helper
# ---------------------------------------------------------------------------
SUMMARY=""
record() { SUMMARY="${SUMMARY}${1}|${2}"$'\n'; }
push_secret() {  # name  status   (value read from stdin)
    local name=$1 status=$2 value
    value=$(cat)
    if [ -z "$value" ]; then
        warn "Refusing to push empty value for ${name}"; record "$name" "SKIPPED"; return
    fi
    printf '%s' "$value" | gh secret set "$name" --repo "$REPO_SLUG"
    ok "Set ${BOLD}${name}${RESET}"; record "$name" "$status"
}
EXISTING_SECRETS=$(gh secret list --repo "$REPO_SLUG" --json name --jq '.[].name' 2>/dev/null || true)
has_secret() { echo "$EXISTING_SECRETS" | grep -qx "$1"; }

# ---------------------------------------------------------------------------
# Step 1: keychain password (auto-generated, random)
# ---------------------------------------------------------------------------
header "Step 1 — Keychain Password (auto-generated)"
say "A random throw-away password the CI runner uses to unlock the temporary"
say "keychain it imports your .p12 into. You never need this value."
openssl rand -base64 24 | tr -d '\n' | push_secret "MACOS_KEYCHAIN_PASSWORD" "SET-GENERATED"

# ---------------------------------------------------------------------------
# Step 2: Sparkle Ed25519 keypair
# ---------------------------------------------------------------------------
header "Step 2 — Sparkle EdDSA Keypair"
SPARKLE_KEY_FILE="${REPO_ROOT}/sparkle_private_key"
SPARKLE_PUB_PLIST="${REPO_ROOT}/HiddenBarIcons/Resources/Info.plist"

# Reconstructs the Ed25519 public key (base64) from a base64 32-byte seed file,
# so we can confirm it matches SUPublicEDKey before shipping. Echoes "" on any
# problem (e.g. legacy 96-byte key) — verification is best-effort.
derive_pubkey() {  # path-to-private-key-file
    python3 - "$1" <<'PYEOF' 2>/dev/null || true
import base64, subprocess, sys, tempfile, os
seed = base64.b64decode(open(sys.argv[1]).read().strip())
if len(seed) != 32:
    sys.exit(0)
pkcs8 = bytes.fromhex("302e020100300506032b657004220420") + seed
pem = "-----BEGIN PRIVATE KEY-----\n" + base64.b64encode(pkcs8).decode() + "\n-----END PRIVATE KEY-----\n"
with tempfile.NamedTemporaryFile("w", suffix=".pem", delete=False) as f:
    f.write(pem); path = f.name
try:
    der = subprocess.check_output(["openssl", "pkey", "-in", path, "-pubout", "-outform", "DER"], stderr=subprocess.DEVNULL)
    print(base64.b64encode(der[-32:]).decode())
finally:
    os.unlink(path)
PYEOF
}

plist_pubkey() {
    /usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$SPARKLE_PUB_PLIST" 2>/dev/null || true
}

generate_sparkle_key() {  # writes new key to $SPARKLE_KEY_FILE, prints public key
    local pem="${TMPDIR}/ed25519.pem"
    openssl genpkey -algorithm ED25519 -out "$pem"
    python3 - "$pem" "$SPARKLE_KEY_FILE" <<'PYEOF'
import base64, subprocess, sys
pem_path, out_path = sys.argv[1], sys.argv[2]
priv = subprocess.check_output(["openssl", "pkey", "-in", pem_path, "-outform", "DER"])[-32:]
pub  = subprocess.check_output(["openssl", "pkey", "-in", pem_path, "-pubout", "-outform", "DER"])[-32:]
open(out_path, "w").write(base64.b64encode(priv).decode())
print(base64.b64encode(pub).decode())
PYEOF
    chmod 600 "$SPARKLE_KEY_FILE"
}

SPARKLE_STATUS="SET-FROM-FILE"
EXISTING_PUB="$(plist_pubkey)"

if [ -f "$SPARKLE_KEY_FILE" ] && [ -s "$SPARKLE_KEY_FILE" ]; then
    ok "Found existing private key at ${DIM}${SPARKLE_KEY_FILE}${RESET} — re-using it."
    SPARKLE_STATUS="REUSED"
elif [ -n "$EXISTING_PUB" ]; then
    say "Info.plist already pins a public key (${BOLD}SUPublicEDKey${RESET}):"
    echo "    ${EXISTING_PUB}"
    say "Provide the matching ${BOLD}private${RESET} key file (base64 of the 32-byte seed)."
    say "Leave blank to GENERATE a new keypair (this rewrites SUPublicEDKey — only do"
    say "this if no one is running a build signed with the old key yet)."
    printf '%sPath to existing Sparkle private key file (or blank to regenerate):%s ' "$BOLD" "$RESET"
    read -r SP_PATH
    SP_PATH=$(printf '%s' "$SP_PATH" | sed -e 's/^"//' -e 's/"$//' -e "s/\\\\\\([[:space:]]\\)/\\1/g")
    if [ -n "$SP_PATH" ]; then
        [ -f "$SP_PATH" ] || fail "Not a file: ${SP_PATH}"
        cp "$SP_PATH" "$SPARKLE_KEY_FILE"; chmod 600 "$SPARKLE_KEY_FILE"
        DERIVED="$(derive_pubkey "$SPARKLE_KEY_FILE")"
        if [ -n "$DERIVED" ] && [ "$DERIVED" != "$EXISTING_PUB" ]; then
            warn "This private key derives public key '${DERIVED}',"
            warn "which does NOT match Info.plist '${EXISTING_PUB}'. Updates would be rejected."
            warn "Double-check you exported the right key."
        elif [ -n "$DERIVED" ]; then
            ok "Verified: private key matches SUPublicEDKey in Info.plist."
        fi
        SPARKLE_STATUS="SET-FROM-FILE"
    else
        warn "Generating a NEW keypair and rewriting SUPublicEDKey in Info.plist."
        NEW_PUB="$(generate_sparkle_key)"
        /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey ${NEW_PUB}" "$SPARKLE_PUB_PLIST"
        ok "Updated Info.plist SUPublicEDKey to: ${NEW_PUB}"
        warn "Rebuild + re-release so shipped apps embed the new key. Run \`xcodegen generate\` if needed."
        SPARKLE_STATUS="SET-GENERATED"
    fi
else
    say "No private key and no SUPublicEDKey found — generating a fresh keypair."
    NEW_PUB="$(generate_sparkle_key)"
    /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey ${NEW_PUB}" "$SPARKLE_PUB_PLIST" 2>/dev/null \
        || /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string ${NEW_PUB}" "$SPARKLE_PUB_PLIST"
    ok "Wrote SUPublicEDKey to Info.plist: ${NEW_PUB}"
    SPARKLE_STATUS="SET-GENERATED"
fi
push_secret "SPARKLE_PRIVATE_KEY" "$SPARKLE_STATUS" < "$SPARKLE_KEY_FILE"
say "${DIM}Back up sparkle_private_key to your password manager — it is gitignored and unrecoverable.${RESET}"

# ---------------------------------------------------------------------------
# Step 3: Developer ID Application .p12
# ---------------------------------------------------------------------------
header "Step 3 — Developer ID Application Certificate (.p12)"
say "The .p12 you exported from Keychain Access (cert+key for ${BOLD}Developer ID Application${RESET})."
while true; do
    printf '%sPath to Developer ID Application .p12 file:%s ' "$BOLD" "$RESET"
    read -r P12_PATH
    P12_PATH=$(printf '%s' "$P12_PATH" | sed -e 's/^"//' -e 's/"$//' -e "s/\\\\\\([[:space:]]\\)/\\1/g")
    [ -z "$P12_PATH" ] && { warn "Empty path. Try again."; continue; }
    [ ! -f "$P12_PATH" ] && { warn "Not a file: ${P12_PATH}"; continue; }
    break
done
printf '%s.p12 export passphrase (input hidden):%s ' "$BOLD" "$RESET"
stty -echo 2>/dev/null || true; read -r P12_PASS; stty echo 2>/dev/null || true; printf '\n'
if ! openssl pkcs12 -in "$P12_PATH" -nokeys -passin "pass:${P12_PASS}" -legacy -info >/dev/null 2>&1 \
   && ! openssl pkcs12 -in "$P12_PATH" -nokeys -passin "pass:${P12_PASS}" -info >/dev/null 2>&1; then
    fail ".p12 + passphrase combination is not valid — openssl could not read it."
fi
ok ".p12 + passphrase accepted by openssl"
base64 -i "$P12_PATH" | tr -d '\n' | push_secret "MACOS_CERTIFICATE_P12_BASE64" "SET-FROM-FILE"
printf '%s' "$P12_PASS" | push_secret "MACOS_CERTIFICATE_P12_PASSWORD" "SET-FROM-INPUT"

# ---------------------------------------------------------------------------
# Step 4: App Store Connect API key for notarization
# ---------------------------------------------------------------------------
header "Step 4 — App Store Connect API Key (notarization)"
say "From App Store Connect → Users and Access → Integrations → Team Keys:"
say "the ${BOLD}Issuer ID${RESET}, the ${BOLD}Key ID${RESET}, and the downloaded ${BOLD}.p8${RESET} file."
printf '%sIssuer ID:%s ' "$BOLD" "$RESET"; read -r ISSUER_ID
[ -z "$ISSUER_ID" ] && fail "Issuer ID cannot be empty."
printf '%sKey ID:%s ' "$BOLD" "$RESET"; read -r KEY_ID
[ -z "$KEY_ID" ] && fail "Key ID cannot be empty."
while true; do
    printf '%sPath to .p8 file:%s ' "$BOLD" "$RESET"
    read -r P8_PATH
    P8_PATH=$(printf '%s' "$P8_PATH" | sed -e 's/^"//' -e 's/"$//' -e "s/\\\\\\([[:space:]]\\)/\\1/g")
    [ -z "$P8_PATH" ] && { warn "Empty path. Try again."; continue; }
    [ ! -f "$P8_PATH" ] && { warn "Not a file: ${P8_PATH}"; continue; }
    if ! head -1 "$P8_PATH" | grep -q "PRIVATE KEY"; then
        warn "File does not look like a PEM .p8 (missing 'PRIVATE KEY' header)."
        printf 'Continue anyway? [y/N] '; read -r ANS
        case "$ANS" in y|Y) break ;; *) continue ;; esac
    fi
    break
done
printf '%s' "$ISSUER_ID" | push_secret "MACOS_NOTARY_ISSUER_ID" "SET-FROM-INPUT"
printf '%s' "$KEY_ID"    | push_secret "MACOS_NOTARY_KEY_ID"    "SET-FROM-INPUT"
base64 -i "$P8_PATH" | tr -d '\n' | push_secret "MACOS_NOTARY_KEY_P8_BASE64" "SET-FROM-FILE"

# ---------------------------------------------------------------------------
# Step 5: Homebrew tap PAT (optional)
# ---------------------------------------------------------------------------
header "Step 5 — Homebrew Tap PAT (optional)"
if [ "$SKIP_HOMEBREW_FLAG" -eq 1 ]; then
    say "${DIM}--skip-homebrew passed; not setting HOMEBREW_TAP_TOKEN.${RESET}"
    has_secret "HOMEBREW_TAP_TOKEN" && record "HOMEBREW_TAP_TOKEN" "REUSED (existing)" || record "HOMEBREW_TAP_TOKEN" "SKIPPED"
else
    say "A PAT scoped to your homebrew-tap repo lets the workflow auto-update the cask."
    printf '%sSet HOMEBREW_TAP_TOKEN now?%s [y/N] ' "$BOLD" "$RESET"; read -r ANS
    case "$ANS" in
        y|Y)
            printf '%sHomebrew Tap GitHub PAT (input hidden):%s ' "$BOLD" "$RESET"
            stty -echo 2>/dev/null || true; read -r HOMEBREW_PAT; stty echo 2>/dev/null || true; printf '\n'
            if [ -n "$HOMEBREW_PAT" ]; then
                printf '%s' "$HOMEBREW_PAT" | push_secret "HOMEBREW_TAP_TOKEN" "SET-FROM-INPUT"
            else
                warn "Empty value — not setting HOMEBREW_TAP_TOKEN."; record "HOMEBREW_TAP_TOKEN" "SKIPPED"
            fi
            ;;
        *)
            say "Skipping Homebrew. The Update-Homebrew-Cask step will be a no-op."
            has_secret "HOMEBREW_TAP_TOKEN" && record "HOMEBREW_TAP_TOKEN" "REUSED (existing)" || record "HOMEBREW_TAP_TOKEN" "SKIPPED"
            ;;
    esac
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
header "Summary"
EXPECTED=(MACOS_KEYCHAIN_PASSWORD SPARKLE_PRIVATE_KEY MACOS_CERTIFICATE_P12_BASE64 \
    MACOS_CERTIFICATE_P12_PASSWORD MACOS_NOTARY_ISSUER_ID MACOS_NOTARY_KEY_ID \
    MACOS_NOTARY_KEY_P8_BASE64 HOMEBREW_TAP_TOKEN)
printf '  %-34s %s\n' "Secret" "Status"
printf '  %-34s %s\n' "------" "------"
for name in "${EXPECTED[@]}"; do
    line=$(printf '%s' "$SUMMARY" | grep -E "^${name}\|" | tail -1 || true)
    status=${line#*|}; [ -z "$status" ] && status="(not touched)"
    printf '  %-34s %s\n' "$name" "$status"
done
echo
ok "Bootstrap complete. Next: push a v*.*.* tag to trigger the release workflow."
