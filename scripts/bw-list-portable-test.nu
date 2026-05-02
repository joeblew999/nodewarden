#!/usr/bin/env nu
# Portable cross-platform test: same nu syntax as bw-list.nu but with mock
# data so it doesn't need bw/fnox to be installed. Used to verify the script
# runs identically on macOS, Linux, and Windows.

let mock = '[
  {"type": 1, "name": "GITHUB_TOKEN",      "login": {"password": "ghp_xxxxxxxxxxxx12345678"}},
  {"type": 1, "name": "CLOUDFLARE_API_TOKEN","login": {"password": "abc-def-ghi"}},
  {"type": 1, "name": "TAURI_SIGNING_PRIVATE_KEY","login": {"password": "Y2VydCB3aXRoIG5ld2xpbmVz\nbW9yZSBzdHVmZg=="}},
  {"type": 1, "name": "BETTER_AUTH_SECRET","login": {"password": "supersecret"}},
  {"type": 2, "name": "ignore-this-secure-note","secureNote": {"type": 0}}
]'

$mock
| from json
| where type == 1
| each {|it| { name: $it.name, bytes: ($it.login.password? | default "" | str length) } }
| sort-by name
| each {|r| $"  ($r.name)\t($r.bytes) bytes" }
| str join "\n"
| print
