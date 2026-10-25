# claude-chatgpt-image-gen-skill

A [Claude Code](https://claude.com/claude-code) **Skill** that lets Claude drive your own
already-logged-in Chrome (via the built-in `claude-in-chrome` browser tool) to
**chatgpt.com**, generate an image with ChatGPT's native "Create an image" feature,
click ChatGPT's own download button, and automatically save the result to a local
directory you specify — then report back the final absolute file path.

No new browser profile, no separate login, no custom MCP server, no OpenAI API key.
It just automates the exact same web UI you'd click through by hand, in your own
browser, with your own ChatGPT session.

## What it does

1. Opens (or reuses) a `chatgpt.com` tab in your real Chrome.
2. Checks you're logged in (never touches your password — if you're logged out, it
   stops and asks you to log in yourself).
3. Switches into ChatGPT's "Create an image" composer mode and submits your prompt.
4. Polls the page for the generation state (`generating` / `done` / `refused` /
   `stuck`) using a couple of small, safe DOM checks — no screenshots needed for
   this part.
5. Clicks the image's own "Download" button and detects the resulting file by
   diffing your Downloads folder's file list before/after the click (ChatGPT's
   download is a pure client-side blob save — it produces **zero** network
   requests, so that's the only reliable detection method).
6. Moves the file into the directory you asked for and hands you back the real,
   full-resolution PNG path.

## Why this exists (the hard part)

Getting a byte-perfect image out of an authenticated single-page app, through a
computer-use-style browser tool, turns out to have more dead ends than you'd
expect:

- The generated image's `src` is ChatGPT's own authenticated endpoint
  (`/backend-api/estuary/content?...&sig=...`) — it needs your session cookie, so
  a plain `curl`/`Invoke-WebRequest` from outside the browser gets a 403.
- The native right-click "Copy image" context menu is OS-level chrome, invisible
  to the browser tool's accessibility tree — not automatable.
- Returning the image URL (raw, or base64-encoded) through the browser tool's
  JS-eval channel gets blocked by its own safety filter, on both counts.
- The one thing that *does* work — clicking ChatGPT's in-page "Download" button —
  produces no network request at all, so you can't detect it by watching traffic
  either. Filename-snapshot diffing on the Downloads folder is the only signal
  that actually works.

All of this is written up with real repro steps in
[`reference/dom-recon.md`](reference/dom-recon.md), including the dead ends, so
future updates (or a fork for a different site) don't have to re-discover them
the hard way.

## Install

Clone (or copy) this repo directly into your Claude Code skills directory:

```bash
git clone https://github.com/Ruby-Leung/claude-chatgpt-image-gen-skill.git \
  ~/.claude/skills/chatgpt-image-gen
```

(On Windows: `%USERPROFILE%\.claude\skills\chatgpt-image-gen`.)

Requirements:
- Claude Code with the `claude-in-chrome` browser tool connected and logged into
  chatgpt.com in that Chrome profile.
- Windows + PowerShell for the two download-detection scripts
  (`scripts/snapshot-downloads.ps1`, `scripts/capture-download.ps1`). Porting
  them to macOS/Linux is just swapping the "watch the Downloads folder" logic
  for the local shell equivalent — the detection *strategy* (snapshot-diff, not
  network-watching) is the part worth keeping.
- Chrome's "Ask where to save each file before downloading" setting should be
  **off**, otherwise the native save happens behind an OS dialog the browser
  tool can't see or click through.

## Usage

Just ask Claude, in plain language, in any project:

> Generate a cyberpunk cat with ChatGPT and save it to C:\Users\me\Desktop\test-gen

Claude picks up the skill automatically from its description — no slash command
needed.

## Files

| Path | Purpose |
|---|---|
| `SKILL.md` | The skill itself — triggers, workflow, decision tables, common mistakes, troubleshooting |
| `reference/dom-recon.md` | Real recon notes: selectors, the ChatGPT image endpoint, what worked, what didn't, and why |
| `scripts/snapshot-downloads.ps1` | Snapshots the Downloads folder's filenames before the download click |
| `scripts/capture-download.ps1` | Waits for the new stable file, moves + optionally renames it, prints the final path |

## License

MIT — see [LICENSE](LICENSE).
