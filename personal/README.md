# CheatCode — interactive SSH chat MVP

This is an additive personal modification of cmux, based on upstream commit
`c5fd30b26e1ab19b4e2d31e38bf2f92b9f2f5edd` (inspected 2026-11-01).
Open **File → CheatCode…** in the full fork. The separate **CheatCode** executable builds the same SwiftUI chat with Command Line
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

## Native interface

Version 0.3 adapts the owner's [Axiom Desktop design](https://github.com/astrea-foundation/axiom-desktop/tree/21f8136fbfdde6530e96b4df14a92a9b661a79b0):
glass stage and composer, exact light/dark color tokens, 22 px corner radii,
DM Sans / PP Cirka typography, circular send control and eased transitions.
The interface is explicitly **English**, independent of the macOS language.
It uses an original chat/terminal mark and app icon; no Axiom logos are bundled.
Asset attribution and font licenses are in `personal/Assets/`.

The native editor grows with text up to a bounded height, supports undo and
selection, sends on Return, and inserts a newline on Shift-Return. Return during
IME composition stays with the input method. Attachments can be removed before
sending. Subtle hover, focus, button and sidebar animations respect the macOS
Reduce Motion preference. The engine label says Claude Code rather than offering
a model picker that the bridge cannot control.

## Chat archive

Version 0.4 names the native app **CheatCode**, keeping the original bundle ID,
connection settings and project history. Use a chat’s **⋯ → Archive chat**
(or right-click it) to move it into that project’s **Archive** section.
Open Archive and use **⋯ → Restore chat** to put it back. Archive starts closed,
stays closed when chats are archived, and shows 20 matching chats per page with
**Load more**. Search filters both lists without forcing the archive open.
Project disclosure is independent of the selected conversation. Archiving the open chat preserves its unsent draft.

Archive membership is private to this Mac and persists in `config.archive.json`
beside the existing configuration. It does not delete transcripts or files,
stop running CLI sessions, or alter Claude permissions. The separate file also
prevents older previews from erasing archive membership when saving settings.

## Deletion and live feedback (0.5)

Project **⋯ → Remove from app** removes only the local sidebar entry; adding the
same folder again restores its server history. **Delete project from server…**
shows the exact path and requires typing `delete`. It removes the folder, nested
files, matching chat transcripts and uploads, and stops their managed CLI sessions.
The server rejects home/project-container roots, hidden system paths, symlinked
roots, changed targets and mounted subtrees. An archived chat also offers
**Delete permanently**, with the same typed confirmation, retaining repository files.

Deletion is scoped by canonical project path and session UUID. A private preview
records filesystem identities before confirmation; commits validate every target,
serialize lifecycle changes and keep retry receipts for a lost SSH response.
Tombstones prevent late hooks from recreating deleted chat state. Unrelated
Claude global account logs/settings are not edited; chat deletion removes its
transcript, per-session transcript directory and CheatCode uploads/metadata.

Sending immediately adds a local user bubble and displays sending/uploading or
working/tool activity. Transcript acknowledgement reconciles the echo without
duplicating it. Delivery errors never automatically resend; an uncertain message
stays visible with a terminal-check notice and **Restore draft**. New assistant
text reveals quickly (up to 1.2 seconds), respecting Reduce Motion. This is a
presentation animation of actual received transcript text, not token streaming;
the real CLI remains the source of message content and permission state.

## Daily launch and shutdown

Version 0.3.1 reconnects automatically and restores the last selected project
and chat. Opening history does not automatically start a new CLI or approve any
prompt. Ended sessions still require **Resume session**. A fresh install opens
Connection settings; failed connections remain retryable.

On macOS, SSH uses `UseKeychain=yes` and `AddKeysToAgent=yes`, retaining strict
host verification and no agent forwarding. If the key password is only in the
current agent, run `personal/scripts/finish-login.command` once. It asks the user
before saving that key password using Apple's `ssh-add --apple-use-keychain`,
then tests access with `IdentityAgent=none`. No password is embedded in the
launcher or app configuration. See [Apple's SSH Keychain documentation](https://developer.apple.com/library/archive/technotes/tn2449/_index.html).

The Mac can be shut down while the VPS stays running. Sent messages and files
remain on the VPS; unsent drafts and attachment selections are not persisted.
The Mac only needs access to the VPS; Claude's provider connection is remote.

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
4. Use **Add project** next to search. Choose **Repository** to clone an HTTPS
   or SSH URL, **New folder** to create a project directory, or **Existing folder**
   to browse the VPS. Review its name and absolute folder, then **Add project**.
   The selected folder is always visible below the project name. All chats in
   one project share its files; different projects can use different folders.
5. Choose **New chat**. Open terminal whenever Claude needs first-folder trust,
   permissions or an answer to a question. Trust is never approved by the app.
6. Select files with the **paperclip**, or drop them onto the composer, then Send. The app never automatically
   resends a message after an uncertain SSH failure; inspect the terminal first.

### Importing repositories yourself

Git must be installed on the VPS. `personal/scripts/bootstrap-git-ubuntu.sh`
provides an optional user-local Git/GitHub CLI on a compatible Ubuntu host.
For private GitHub repositories, **Sign in to GitHub…** opens a normal SSH
terminal running GitHub's device login. Complete that login yourself, then use
an HTTPS repository URL. Provider credentials stay on the VPS; never embed a
password/token in a URL. SSH URLs require the VPS to have its own trusted host
entry and appropriate key. No Mac SSH agent is forwarded.

Clone runs as a detached worker so a brief SSH interruption does not restart it.
**Check import** recovers the original job after uncertain delivery. **Cancel**
stops that worker's Git process group. Existing folders are never overwritten;
partial data remains recoverable. Clones have a ten-minute limit, skip LFS file
smudging and recursive submodules, and do not run repository hooks/templates.
Large LFS files, submodules and subsequent Git operations remain available in
the interactive terminal or through Claude under its regular permissions.

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

For a full local tagged build, run `personal/scripts/apply-personal-branding.sh`
in the build checkout first; the GitHub workflow does this automatically.

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
