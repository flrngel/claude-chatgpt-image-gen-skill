---
name: chatgpt-image-gen
description: >
  Drive the user's already-logged-in real Chrome via claude-in-chrome, open
  chatgpt.com, generate an image using ChatGPT's native "Create an image"
  capability, click the image's built-in download button to save the file to a
  local directory specified by the caller, and report the final absolute path.
  Trigger phrases: "use chatgpt to generate/draw an image", "chatgpt image
  generation", "draw on chatgpt.com", and "help me use ChatGPT to generate an
  image and save it to xxx". This skill operates the web UI rather than calling
  the OpenAI API/SDK directly; if the user wants API or provider-based image
  generation (for example `arkcli +gen` for Volcano Ark or Doubao), do not use
  this skill.
---

# ChatGPT web image generation (claude-in-chrome + automatic save)

## Overview

Use claude-in-chrome to operate the user's currently logged-in real Chrome,
open chatgpt.com, generate an image using ChatGPT's native "Create an image"
feature, click the image's in-page download button to save it locally, and then
report the final absolute file path to the user. The process does not require a
new browser profile, a re-login, or any custom MCP server.

This is a general-purpose skill and is not tied to any specific project branding.

## When to use / When NOT to use

- Use: the user wants to "generate an image with ChatGPT and save it to a local directory".
- Do not use: the user wants to call the OpenAI API/SDK directly — that is pure code integration and does not require browser automation.
- Do not use: the user wants to use Volcano Ark / Doubao image generation — use `arkcli +gen` instead.
- Do not use: the user wants Sora video generation — that is on sora.chatgpt.com, outside the scope of this skill.

## Prerequisites

- The user's Chrome must have the claude-in-chrome extension installed and must
  already be logged into ChatGPT in that browser profile. It is not enough for
  the user to be signed in on some other device or window; it must be the exact
  Chrome instance being driven by claude-in-chrome. Claude must never auto-fill
  account credentials — if the user is not logged in, stop and ask them to log
  in manually before retrying.
- If `list_connected_browsers` shows more than one Chrome instance, you must use
  `AskUserQuestion` to list each connected browser and ask the user to select the
  correct one before proceeding. This is a tool rule and cannot be bypassed.
- The user's Chrome download setting "Ask where to save each file before
  downloading" should be turned off; otherwise the native download triggers an
  OS-level dialog that claude-in-chrome cannot see or click, which will stall the
  flow. If this setting is suspected to be enabled, ask the user to disable it in
  `chrome://settings/downloads`.

## Parameters

| Parameter | Required | Description |
|---|---|---|
| `prompt` | Yes | The natural-language image description, pasted directly into ChatGPT's "Create image" composer |
| `save_dir` | Yes | The destination directory (absolute path); it will be created automatically if missing |
| `filename` | No | If omitted, ChatGPT's default filename is used (`ChatGPT Image <Mon> <D>, <YYYY>, <hh>_<mm>_<ss> <AM/PM>.png`) |
| `new_conversation` | No, default `true` | `true` opens a new tab in a new conversation; `false` reuses the user's already-open chatgpt tab (only if the user explicitly requests it) |
| `max_wait_seconds` | No, default `180` | Generation timeout; a single image generation takes about 63 seconds in practice, so 180 seconds leaves adequate margin |
| `keep_tab_open` | No, default `true` | Whether to close the newly created tab after completion |
| `reference_image_path` | No | Local reference image path for image-to-image generation via "Upload a photo" — the exact upload interaction has not been verified yet; when encountered, inspect with `find` first instead of hard-coding steps |
| `count` / `aspect_ratio` | No | The ChatGPT web UI does not currently expose dedicated controls for quantity or aspect ratio; these must be specified in the prompt text instead and may not be honored |

All parameter details and known selectors must follow `reference/dom-recon.md`.
That document records the real test date; if a selector fails twice in a row,
update that file first instead of editing this table directly.

## Workflow

1. **Load tools**: use a single `ToolSearch` call to load
   `tabs_context_mcp,navigate,computer,read_page,find,javascript_tool,tabs_create_mcp,tabs_close_mcp`.
   If a reference image is needed, also add `file_upload`. Do not load tools one by one.
2. **Confirm the browser**: run `list_connected_browsers`. Even when only one Chrome is connected and `isLocal:true`, it is still advisable to use `AskUserQuestion` to confirm it (this is a tool rule), so you do not operate someone else's browser by mistake.
3. **Create a tab**: use `tabs_context_mcp({createIfEmpty:true})` and then `tabs_create_mcp()` unless the user explicitly wants to reuse an already-open chatgpt tab.
4. **Open the home page and check login state**: `navigate` to `https://chatgpt.com`, wait 2–3 seconds, and take a quick `computer(screenshot)`. If the top-right shows `Log in` / `Sign up for free`, the user is not logged in; stop and ask them to log in manually. Otherwise, continue.
5. **Enter Create image mode**: use `find("Create an image button")` or click the homepage composer shortcut `Create an image` button directly; after clicking, the composer should show an unremovable `Create image` pill.
6. **Enter the prompt and submit**: place the cursor after the pill, `computer(type, text=prompt)`, and then click the send arrow (or `find("send button")`).
7. **Poll for generation status** (every 3–5 seconds until `max_wait_seconds`):
   ```js
   // javascript_tool text argument
   (() => {
     const main = document.querySelector('main');
     const stopBtn = document.querySelector('[data-testid="stop-button"]');
     const imgs = main.querySelectorAll('img[alt^="Generated image"]');
     return JSON.stringify({ generating: !!stopBtn, imgCount: imgs.length });
   })()
   ```
   - `generating:true` → keep waiting.
   - `generating:false, imgCount:0` → no image was produced: read the last assistant turn (`section[data-turn="assistant"]`) and report its plain text as the reason, then stop. This may be a content policy refusal or another unknown block; do not invent reasons like "quota exhausted" unless you have observed them.
   - `generating:false, imgCount>0` → generation succeeded; proceed to the download step.
   - If `generating:true` persists beyond `max_wait_seconds` → consider the generation stuck, stop, and tell the user it was abandoned (optionally retry in a fresh conversation once).
8. **Download** (core step: use only this route; do not try alternatives — see "Common mistakes"):
   1. Run `scripts/snapshot-downloads.ps1` via Bash/PowerShell and record the Downloads path it prints.
   2. Use `find("Share this image button")` to locate the image's share/export icon in the hover toolbar at the lower-right corner, then `computer(left_click, ref=...)` to click it.
   3. Use `javascript_tool` to run `document.querySelectorAll('[role="dialog"]').length` and confirm the dialog is open. Do not rely on screenshots here; the dialog often fails to render correctly or stalls the screenshot tool.
   4. Use `find("Download button in image dialog")` to locate the `Download` button, then `computer(left_click, ref=...)` to click it.
   5. Run `scripts/capture-download.ps1 -SnapshotPath <previous_path> -DestDir <save_dir> [-DestFileName <filename>]` in Bash/PowerShell and read the final absolute path printed by the script.
9. **Verify and report**: confirm that the returned path exists and has non-zero size (the script already performs this validation internally, so a valid returned path is effectively a pass). Share the absolute path with the user.
10. **Close up**: use `keep_tab_open` to decide whether to call `tabs_close_mcp` and close the newly created tab.

## Boundary cases

| Situation | Handling |
|---|---|
| Not logged in | Stop, ask the user to log in manually, and never auto-fill account credentials |
| Content policy refusal / no image produced | Read the assistant turn text and report the reason; do not rephrase or evade the refusal by guessing |
| A boundary request is "softly rewritten" (for example, a reference to a real person without naming them) | ChatGPT often does not hard-reject these; it rewrites them into a fictional version and continues normally. Treat this as normal generation success and do not special-case it |
| Generation stalls beyond `max_wait_seconds` | Stop and tell the user it was abandoned; optionally retry once in a new conversation |
| Multiple browsers are connected | Follow the `list_connected_browsers` rule and ask the user to choose the correct browser via `AskUserQuestion` |
| CAPTCHA / human-challenge prompt appears | Stop immediately and tell the user; do not attempt a forced retry |
| Repeated CDP screenshot timeouts (`renderer frozen`) | Retry 1–2 times; if it still fails, open a new tab with `tabs_create_mcp`, `navigate` to the same conversation URL (`https://chatgpt.com/c/<uuid>`), and close the bad tab instead of waiting forever |
| `find` / selector fails twice in a row | Stop and tell the user that the ChatGPT page structure may have changed and that DOM recon needs to be redone; do not keep retrying or guessing new selectors |
| "Ask where to save each file before downloading" is enabled in the browser | This creates an OS dialog that claude-in-chrome cannot see, causing the flow to stall; tell the user to disable it at `chrome://settings/downloads` |
| The same `save_dir` is reused and a filename collision occurs | `capture-download.ps1` already handles this by auto-appending a numeric suffix instead of overwriting the file |

## Common mistakes

- Do not try to bypass the browser and use `Invoke-WebRequest`/curl to download the image URL directly — that endpoint is owned by ChatGPT and requires the browser session cookie; without it, you get a 403.
- Do not try to automate "right-click → Copy image" — the native context menu is OS-rendered and does not appear in claude-in-chrome's `find` / `read_page` view, so it cannot be clicked.
- Do not try to pass the image URL (even if base64-encoded) back out of the browser via the `javascript_tool` return value — the literal result is blocked as `[BLOCKED: Cookie/query string data]`, and base64-encoded versions are blocked as `[BLOCKED: Base64 encoded data]`. This route is a dead end; do not waste time retrying it.
- Do not use fixed pixel coordinates to click the share icon or download button — coordinates change with conversation length and window size. Always use `find` + `ref`.
- Do not use `computer(screenshot)` to determine whether the image viewer dialog is open — it often renders incorrectly or causes the screenshot tool to time out. Instead, use `javascript_tool` to inspect the `[role="dialog"]` count or use `find` directly.
- Do not use "Did a new network request appear after clicking download?" as the success signal — this image download is a pure front-end blob operation and `read_network_requests` shows no trace whatsoever. The only reliable method is a before/after filename snapshot diff on the Downloads folder (`scripts/snapshot-downloads.ps1` + `scripts/capture-download.ps1` already encapsulate this).
- Do not use a generic `main img` count to decide whether a new image was generated — the same image may render as 2–3 physical `<img>` elements while it is still loading. Use the precise selector `img[alt^="Generated image"]` instead.
- If the login state is uncertain, do not guess — use a screenshot to confirm manually or ask the user. Never attempt a login automatically.
- If a CAPTCHA or human verification challenge appears, stop immediately and do not try to brute-force a retry.

## Quick troubleshooting

| Error / symptom | Cause | Response |
|---|---|---|
| `CDP sendCommand "Page.captureScreenshot" timed out" / "renderer may be frozen"` | Common immediately after opening the image viewer dialog and taking a screenshot too quickly | Retry 1–2 times; if it still fails, open a new tab with `navigate` to the same conversation URL and close the old one |
| `javascript_tool` returns `[BLOCKED: Cookie/query string data]` or `[BLOCKED: Base64 encoded data]` | The code tried to send sensitive or high-entropy strings (URL or base64 data) back out of the browser | Stop returning that data; this skill does not need to do so |
| `capture-download.ps1` reports "No new stable download detected" | The download button was not clicked correctly (stale ref or the dialog did not actually open), or the browser has "Ask where to save each file before downloading" enabled | Confirm with `javascript_tool` that `[role="dialog"]` exists and click the button again; also check the Chrome download settings |
| The image request hangs in "Thinking" for more than 3 minutes with no result | In rare cases the ChatGPT backend becomes stuck | Retry once in a new conversation; if it still fails, stop and tell the user |
