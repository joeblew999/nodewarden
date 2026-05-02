#!/usr/bin/env nu
# Pilot port: bw:list (currently bash in joeblew999/.github/mise-tasks/bw/list)
#
# Side-by-side experiment to compare ergonomics. The bash version stays
# canonical; this is a parallel implementation for evaluation only.

# Load BW_SESSION from fnox (suppressing 'set -e' equivalent via try/catch)
let session = (try { ^fnox get BW_SESSION | str trim } catch { "" })
if ($session | is-empty) {
  print --stderr "✗ no BW_SESSION — run 'mise run bw:bootstrap'"
  exit 1
}
$env.BW_SESSION = $session

# Confirm vault is unlocked (no jq needed — bw status already JSON, parsed natively)
let status = (^bw status | from json)
if ($status.status != "unlocked") {
  print --stderr "✗ vault locked — run 'mise run bw:unlock'"
  exit 1
}

# Pull items → filter logins → derive name + size → sort → format
^bw list items
| from json
| where type == 1
| each {|it| { name: $it.name, bytes: ($it.login.password? | default "" | str length) } }
| sort-by name
| each {|r| $"  ($r.name)\t($r.bytes) bytes" }
| str join "\n"
| print
