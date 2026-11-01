# cmux Personal — interactive SSH chat MVP

This is an additive personal modification of cmux, based on upstream commit
`c5fd30b26e1ab19b4e2d31e38bf2f92b9f2f5edd` (inspected 2026-11-01).
Open **File → Personal Claude Chat…** in the full fork. The separate **cmux
Personal Preview** executable builds the same SwiftUI chat with Command Line
Tools and uses Terminal.app for the terminal button. It is a verification and
early-use build, not a replacement for the full Ghostty-based cmux application.

## What this MVP does

- Native SwiftUI project sidebar, saved conversations, session switching, text
  composer, inline Markdown styling and tool-name activity rows.
- Connects over SSH as `developer`; Claude Code runs interactively in a private
  `tmux -L cmux-personal` server. The command uses `--session-id` or `--resume`.
  It never uses `-p`, stream-json, the Agent SDK, an Anthropic proxy or an API key.
- Tails Claude's own JSONL history on the VPS. Disconnecting the Mac leaves the
  remote session alive; selecting a saved session and Resume restarts a finished
  CLI with its original ID.
- Uploads explicitly selected files (20 MiB each) through SSH, with random private
  directories and mode 0600. The prompt includes exact remote paths for Claude
  to read under its regular permission rules. Files stay on the VPS until the
  user deletes them; removal from the composer does not delete past uploads.
- Uses Claude hooks to gate input while busy or awaiting permission. Approvals,
  questions, slash-command pickers, initial trust and MCP sign-in remain in the
  real terminal. No tool is approved by the bridge. Existing Claude user/project
  permissions still apply. Stop sends Escape; it never kills the remote server.

## First use

1. Ensure `ssh developer@YOUR_HOST` works with a trusted known_hosts entry. Verify
   a new host's fingerprint through your VPS provider before accepting it.
   Unlock an encrypted key with `ssh-add /path/to/key`; this app does not ask for
   or retain the passphrase. SSH aliases and keys from your existing SSH setup
   are supported. Authentication must work without an interactive password.
2. Install Claude Code and Python 3 on the VPS and sign into Claude there.
   Install tmux normally, or run `personal/scripts/bootstrap-ubuntu.sh` on a
   compatible Ubuntu host for a user-local installation without sudo.
3. In Connection, enter the host/alias, port and optional key path. Click Connect.
   The app installs its small Python hook helper under
   `~/.local/share/cmux-personal/` on the VPS. There is no network listener.
4. Add a project with an existing absolute VPS path, for example
   `/home/developer/projects/my-project`, then New chat. Open terminal whenever
   Claude needs startup confirmation, permissions or an answer to a question.
5. Select files with the paperclip, then Send. The app never automatically
   resends a message after an uncertain SSH failure; inspect the terminal first.

Local settings are stored in `~/Library/Application Support/cmux-personal/config.json`
with owner-only permissions. They contain host, key **path** and project metadata,
not passwords, key contents or provider tokens. Transcript contents stay remote
and in app memory. This fork does not upload them to a custom backend.

## Krea and ElevenLabs

Run `personal/scripts/configure-mcp.sh` on the VPS as developer. It adds missing
user-scoped server entries without replacing existing ones:

- Krea: `https://api.krea.ai/mcp` ([official setup](https://www.krea.ai/mcp)).
- ElevenLabs: `https://api.elevenlabs.io/v1/mcp`
  ([official hosted MCP](https://elevenlabs.io/docs/eleven-agents/operate/hosted-mcp)).

Complete sign-in using `/mcp` in the interactive terminal and review each
provider's requested access. Registering a server is not proof that its account
is authenticated. ElevenLabs' hosted endpoint covers agent management and text
to speech; additional media capabilities may require a different official
integration. MCP generation is not exercised by CI and may consume provider
credits. Existing Claude Code permissions govern its tools.

## Build without local Xcode

The workflow `.github/workflows/personal-macos.yml` runs on GitHub-hosted
`macos-26`, with no SSH key, VPS address, Anthropic login or Apple certificate.
It runs bridge tests, builds the native preview, and builds the full fork using
upstream's isolated `reload.sh --tag personal` path. Ghostty checksums and the
upstream cmux-tui artifact provenance are verified. There are separate preview
and full-fork ZIP artifacts. The build is ad-hoc signed, not Apple-notarized.

Push the branch and use **Actions → Personal macOS MVP → Run workflow**, or:

```sh
gh workflow run personal-macos.yml --ref personal/native-ssh-chat -f full_cmux=true
```

A GitHub OAuth token needs the `workflow` scope to push a workflow change. If
that scope is unavailable, retain the prepared commit/patch locally and push
after enabling it. Do not put credentials in repository files or Actions inputs.

For the standalone preview on a Mac with Command Line Tools:

```sh
bash personal/scripts/build-preview.sh /absolute/output/directory
```

## Architecture and upstream findings

The macOS shell is Swift/AppKit with Ghostty. Upstream `agent-chat/` is React/Bun;
its ordinary Claude adapter runs a persistent `claude -p` process. Its separate
terminal-chat adapter reads JSONL and sends input to an existing terminal. That
second principle is retained here, with a native UI and an SSH-only transport.
The new window is independent of upstream's experimental Chat UI flag.

`PersonalChatModel` owns selection and state; `PersonalChatService` owns SSH
requests; `PersonalChatRepository` persists settings; `personal/bridge.py` owns
remote session, transcript and upload operations. The full cmux composition
opens a terminal workspace with an SSH attach command. Executing `exec claude`
as tmux's pane command ensures that a finished agent never drops into a shell
where stale chat text could execute as commands.

The app/CLI and this added code retain **GPL-3.0-or-later**, subject to existing
third-party notices. `web/`, the listed workers and relay services have separate
BUSL terms; this implementation deploys none of those services. Keep LICENSE,
THIRD_PARTY_LICENSES.md and corresponding source with any redistribution.
This is an unofficial personal cmux modification, not an Anthropic product.

## Delivery stages and limits

1. **MVP in this branch:** native UI, SSH/tmux lifecycle, history, attachments,
   guarded composer, terminal permission handoff and cloud-build workflow.
2. **Next:** richer Markdown/code blocks, image/audio previews, native per-tool
   approval cards after validating a stable permission protocol, and pagination.
3. **Hardening:** event-driven incremental transcripts, broader Claude-version
   compatibility, automated real-CLI scenarios, Intel build, signing/notarization.

History refreshes every two seconds, shows the latest 400 rendered entries and
lists up to 100 sessions per project. Transcript files over 32 MiB require the terminal.
The parser follows an internal Claude transcript format, not a stable API;
unknown JSONL records are ignored. Transient transcript edits and compaction
may require additional adaptation. Inline Markdown is supported; media remains
file references in this MVP. Project folders must already exist. The UI has one
configured server. tmux survives disconnects, not a VPS reboot; use Resume after
a reboot. Startup/MCP/trust dialogs must be completed in the terminal. After cancelling
a permission dialog with Escape, Claude may not emit a Stop hook; in that case
the composer deliberately stays blocked until a normal terminal turn completes.

Using the interactive CLI does not establish identical Anthropic quota usage,
eligibility, availability or pricing. Those remain controlled by Anthropic.

## Verification

```sh
python3 -m unittest discover -s personal/tests -v
swiftc -typecheck -swift-version 6 -target arm64-apple-macosx14.0 Sources/PersonalChat/*.swift
python3 scripts/verify-local.py --swift-changed upstream/main
```

The portable tests cover transcript filtering and partial lines, cross-project
isolation, uploads and traversal rejection, terminal control-character rejection,
permission gating, bracketed paste and uncertain-delivery handling. They mock
tmux; a real SSH/Claude smoke test is separately required. Typechecking the new
files proves that component compiles, not that the full cmux app builds.
