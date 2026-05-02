#!/usr/bin/env bash
# Bitwarden CLI bootstrap for this NodeWarden instance.
#
# Idempotent: re-run any time to refresh BW_SESSION (e.g. after laptop reboot).
# All three values are stored in fnox/macOS keychain so subsequent fnox lookups
# work without re-prompting.
#
# Reads the NodeWarden URL from $NODEWARDEN_URL (defaults to the deployed URL
# inferred from the wrangler.toml worker name + your subdomain).
#
# Three hidden-input prompts:
#   1. Personal API client_id      ('user.<UUID>' from NodeWarden Settings)
#   2. Personal API client_secret  (random string, shown once when generated)
#   3. Master password             (used only to derive BW_SESSION, then dropped)
#
# Output side effects:
#   - bw config server <URL>
#   - bw login --apikey  (writes ~/.config/Bitwarden\ CLI session state)
#   - fnox secrets set: BW_CLIENTID, BW_CLIENTSECRET, BW_SESSION
#   - ~/.config/fnox/config.toml gets [providers.bitwarden] block (idempotent)
#
# After this runs, fnox can read secrets via:
#   GITHUB_TOKEN = { provider = "bitwarden", value = "GitHub PAT" }

set -euo pipefail

# Config
URL="${NODEWARDEN_URL:-https://nodewarden.gedw99.workers.dev}"
FNOX_CONFIG="$HOME/.config/fnox/config.toml"

# Locate fnox (installed via mise plugin)
FNOX="${FNOX:-$HOME/.local/share/mise/installs/github-jdx-fnox/1.23.0/fnox}"
if [ ! -x "$FNOX" ]; then
  if command -v fnox >/dev/null 2>&1; then
    FNOX=$(command -v fnox)
  else
    echo "✗ fnox not found — install via 'mise install' (declared in mise.toml)" >&2
    exit 1
  fi
fi

if ! command -v bw >/dev/null 2>&1; then
  echo "✗ bw CLI not found — install via 'mise install' (declared in mise.toml)" >&2
  exit 1
fi

echo "=== Bitwarden CLI bootstrap → $URL ==="
echo
echo "Three hidden prompts:"
echo "  1. Personal API client_id     (looks like 'user.<UUID>')"
echo "  2. Personal API client_secret (random string from 'View API Key')"
echo "  3. Master password            (used to unlock; not stored)"
echo

read -r -s -p "client_id: " BW_CLIENTID; echo
read -r -s -p "client_secret: " BW_CLIENTSECRET; echo
read -r -s -p "master password: " BW_PASSWORD; echo
echo

[ -z "$BW_CLIENTID" ]     && { echo "✗ client_id empty";     exit 1; }
[ -z "$BW_CLIENTSECRET" ] && { echo "✗ client_secret empty"; exit 1; }
[ -z "$BW_PASSWORD" ]     && { echo "✗ master password empty"; exit 1; }

echo "→ ensuring bw is logged out (idempotent)"
bw logout 2>/dev/null || true

echo "→ pointing bw at $URL"
bw config server "$URL" >/dev/null

echo "→ logging in via API key"
export BW_CLIENTID BW_CLIENTSECRET
bw login --apikey 2>&1 | tail -3

echo "→ unlocking vault → BW_SESSION"
# bw --passwordenv requires the env var to be exported, not just shell-local
export BW_PASSWORD
BW_SESSION=$(bw unlock --raw --passwordenv BW_PASSWORD)
unset BW_PASSWORD

[ -z "$BW_SESSION" ] && { echo "✗ unlock failed — bad master password?"; exit 1; }

echo "→ storing all three in fnox keychain (global config)"
printf '%s' "$BW_CLIENTID"     | "$FNOX" set --global -p keychain BW_CLIENTID
printf '%s' "$BW_CLIENTSECRET" | "$FNOX" set --global -p keychain BW_CLIENTSECRET
printf '%s' "$BW_SESSION"      | "$FNOX" set --global -p keychain BW_SESSION

echo "→ adding bitwarden provider to $FNOX_CONFIG"
# fnox's bitwarden provider does NOT accept a 'server' field — the URL is set
# on the bw CLI side via 'bw config server' (done above). fnox just shells out
# to 'bw' which reads its own config. Valid fields per fnox docs: collection,
# organization_id, profile, backend, auth_command.
mkdir -p "$(dirname "$FNOX_CONFIG")"
touch "$FNOX_CONFIG"
if grep -q '^\[providers\.bitwarden\]' "$FNOX_CONFIG"; then
  echo "  ✓ already present"
else
  printf '\n[providers.bitwarden]\ntype = "bitwarden"\n' >> "$FNOX_CONFIG"
  echo "  ✓ appended"
fi

unset BW_CLIENTID BW_CLIENTSECRET BW_SESSION

echo
echo "=== verify (bw status with stored BW_SESSION exported) ==="
SESSION=$("$FNOX" get BW_SESSION)
BW_SESSION="$SESSION" bw status 2>&1 \
  | jq -r '"  status:    \(.status)\n  serverUrl: \(.serverUrl)\n  userEmail: \(.userEmail // "?")"' \
  || echo "  (bw status check skipped — non-fatal)"
unset SESSION
echo
echo "=== fnox state ==="
for k in BW_CLIENTID BW_CLIENTSECRET BW_SESSION; do
  V=$("$FNOX" get "$k" 2>/dev/null || true)
  [ -n "$V" ] && echo "  ✓ $k (${#V} chars)" || echo "  ✗ $k missing"
done
echo
echo "============================================================"
echo "✓ bootstrap complete"
echo "  Next: 'mise run bw:migrate-from-keychain' to copy existing"
echo "        keychain secrets into NodeWarden + rewire fnox config"
echo "============================================================"
