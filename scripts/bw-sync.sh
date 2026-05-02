#!/usr/bin/env bash
# Pull all NodeWarden items → update keychain (idempotent).
# Run this after rotating a secret on iPhone or web vault, OR on a cron, OR
# at shell startup. Reading from keychain stays fast at runtime; this just
# refreshes the local cache against the canonical NodeWarden state.
#
# Skip list (chicken/egg — these stay keychain-only, never read from NodeWarden):
#   BW_CLIENTID, BW_CLIENTSECRET, BW_SESSION
#
# Bash 3.2 compatible (macOS default).
#
# Usage:
#   ./bw-sync.sh --dry-run     show plan, change nothing
#   ./bw-sync.sh               apply
set -euo pipefail

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

FNOX="${FNOX:-$HOME/.local/share/mise/installs/github-jdx-fnox/1.23.0/fnox}"
[ -x "$FNOX" ] || FNOX=$(command -v fnox)

SKIP="${BW_SYNC_SKIP:-BW_CLIENTID,BW_CLIENTSECRET,BW_SESSION}"
SKIP_LF=$(printf '%s' "$SKIP" | tr ',' '\n')
is_skipped() { printf '%s' "$SKIP_LF" | grep -Fxq -- "$1"; }

BW_SESSION=$("$FNOX" get BW_SESSION 2>/dev/null || true)
[ -z "$BW_SESSION" ] && { echo "✗ no BW_SESSION — run 'mise run bw:bootstrap'" >&2; exit 1; }
export BW_SESSION

if ! bw status 2>/dev/null | jq -e '.status == "unlocked"' >/dev/null; then
  echo "✗ vault locked — run 'mise run bw:unlock'" >&2
  exit 1
fi

bw sync >/dev/null 2>&1 || true

[ "$DRY_RUN" = "1" ] && echo "=== DRY RUN — no changes ===" || echo "=== sync NodeWarden → keychain ==="

updated=0; same=0; skipped=0; empty=0

# Stream item rows: tab-separated NAME\tPASSWORD (passwords with tab/newline are escaped by jq @tsv)
while IFS=$'\t' read -r NAME PW; do
  [ -z "$NAME" ] && continue
  if is_skipped "$NAME"; then
    skipped=$((skipped + 1))
    continue
  fi
  if [ -z "$PW" ]; then
    echo "  ⤬ $NAME (empty in NodeWarden)"
    empty=$((empty + 1))
    continue
  fi
  CUR=$("$FNOX" get "$NAME" 2>/dev/null || true)
  if [ "$CUR" = "$PW" ]; then
    same=$((same + 1))
  else
    if [ -z "$CUR" ]; then
      echo "  + $NAME (new in keychain)"
    else
      echo "  ↻ $NAME (keychain differs from NodeWarden — would update)"
    fi
    if [ "$DRY_RUN" = "0" ]; then
      printf '%s' "$PW" | "$FNOX" set --global -p keychain "$NAME" >/dev/null
    fi
    updated=$((updated + 1))
  fi
done < <(bw list items 2>/dev/null | jq -r '.[] | select(.type==1) | [.name, (.login.password // "")] | @tsv')

echo
[ "$DRY_RUN" = "1" ] && echo "=== DRY RUN summary ===" || echo "=== sync complete ==="
printf "  %d updated / %d already-in-sync / %d skipped / %d empty\n" \
  "$updated" "$same" "$skipped" "$empty"
