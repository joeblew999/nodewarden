#!/usr/bin/env bash
# Write-through: hidden-input prompt → set in NodeWarden + mirror to keychain.
# Use this to rotate a secret on Mac. Both stores end up consistent in one shot.
# (Rotating via the iPhone app or web vault → run 'mise run bw:sync' afterwards.)
#
# Usage:
#   ./bw-set.sh GITHUB_TOKEN
set -euo pipefail

NAME="${1:-}"
[ -z "$NAME" ] && { echo "usage: bw-set.sh <NAME>" >&2; exit 1; }

FNOX="${FNOX:-$HOME/.local/share/mise/installs/github-jdx-fnox/1.23.0/fnox}"
[ -x "$FNOX" ] || FNOX=$(command -v fnox)

BW_SESSION=$("$FNOX" get BW_SESSION 2>/dev/null || true)
[ -z "$BW_SESSION" ] && { echo "✗ no BW_SESSION — run 'mise run bw:bootstrap'" >&2; exit 1; }
export BW_SESSION

if ! bw status 2>/dev/null | jq -e '.status == "unlocked"' >/dev/null; then
  echo "✗ vault locked — run 'mise run bw:unlock'" >&2
  exit 1
fi

read -r -s -p "value for $NAME (hidden): " VAL; echo
[ -z "$VAL" ] && { echo "✗ empty value — aborting"; exit 1; }

bw sync >/dev/null 2>&1 || true

# Find existing by exact name match
EXISTING_ID=$(bw list items --search "$NAME" 2>/dev/null \
  | jq -r --arg n "$NAME" '.[] | select(.type==1 and .name==$n) | .id' \
  | head -1)

if [ -n "$EXISTING_ID" ]; then
  echo "→ updating NodeWarden item $NAME ($EXISTING_ID)"
  bw get item "$EXISTING_ID" \
    | jq --arg pw "$VAL" '.login.password = $pw' \
    | bw encode \
    | bw edit item "$EXISTING_ID" >/dev/null
else
  echo "→ creating new NodeWarden item $NAME"
  jq -n --arg name "$NAME" --arg pw "$VAL" \
    '{type: 1, name: $name, notes: "managed by fnox+bw; rotate via mise run bw:set", login: {username: "", password: $pw, uris: []}, fields: [], favorite: false, reprompt: 0}' \
    | bw encode \
    | bw create item >/dev/null
fi

echo "→ mirroring to keychain"
printf '%s' "$VAL" | "$FNOX" set --global -p keychain "$NAME" >/dev/null
unset VAL

echo "✓ $NAME set in NodeWarden + keychain"
