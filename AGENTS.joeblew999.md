# AGENTS.joeblew999.md — branch-local agent guide

Operational brief for any AI agent working on the `joeblew999` branch of `nodewarden`.

**Project guidance:** follow upstream project instructions and this branch-local guide.
The former shared mise library is retired; see [MISE-RETIREMENT.md](MISE-RETIREMENT.md).

## What this repo is

Bitwarden-compatible self-hosted server fork. Uses bw:* shared tasks for keychain ↔ NodeWarden sync. Deploy via 10-deploy + bw:bootstrap on a fresh machine.

## Branch-local quirks

Only consumer that pulls bw:* + the only one needing npm:@bitwarden/cli pinned.

## Mise wiring

[mise.toml](mise.toml) contains only local tasks. The shared pre-push `check`
wrapper has been retired; run the project checks appropriate to your changes.
