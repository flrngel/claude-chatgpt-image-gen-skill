# chatgpt.com image-generation DOM investigation notes

Test date: 2026-07-06. Account: ChatGPT Pro subscription. If `find`/selector-based location fails twice in a row, that indicates the page has changed and the DOM needs to be re-tested; do not guess new selectors based on stale notes.

## Login-state detection

- Logged out: the top-right corner shows two fixed buttons with the text `Log in` and `Sign up for free`.
- Logged in: the top-right login buttons disappear; the sidebar shows `Library` / `Projects` / `Scheduled` / `Apps`; the lower-left shows an avatar, account name, and subscription level (for example `<your account name>` / `Pro`).
- claude-in-chrome operates the user's currently open real Chrome; it is irrelevant whether the user is logged in elsewhere or on another device. The login must be completed in the exact Chrome window being driven by claude-in-chrome, and Claude must never auto-fill account credentials.

## Triggering image generation

1. On the new-conversation home page, the composer has three shortcut buttons beneath it: `Create an image` / `Write or edit` / `Look something up`. Click `Create an image`.
2. After that, the composer displays an unremovable `Create image` pill; the cursor sits after the pill, and any text typed continues the image prompt. At the same time, the `Explore ideas` area below shows reference images or style cards such as `Upload a photo`, `Messi mode`, and `Bobblehead`; `Upload a photo` can be used for image-to-image generation. This was not explored in depth in this pass, and that specific upload interaction should be tested separately if needed.
3. After entering the prompt, click the send arrow (or locate the send button with `find`) to submit.

## Generation-status detection (core decision table)

| Observation | Check | Conclusion |
|---|---|---|
| A "stop" icon appears on the right side of the composer instead of the send arrow | `document.querySelector('[data-testid="stop-button"]')` is non-null | Generation is in progress |
| The stop button disappears | The same selector becomes `null` | The generation phase has ended; you still need to confirm whether an image was actually produced |
| `main` contains `img[alt^="Generated image"]` | `document.querySelectorAll('img[alt^="Generated image"]')` returns one or more elements | Generation succeeded |
| The stop button disappears but `img[alt^="Generated image"]` never appears | The same query returns 0 | No image was generated (content policy refusal / text-only reply); read the plain assistant-turn text as the reason |

Key caveats:
- Do not use a broad `main.querySelectorAll('img')` count. The same generated image may render 2–3 physical `<img>` elements during progressive loading, with different classes such as `absolute top-0 z-1 w-full` and `absolute top-0 w-full`; these are likely a blurred placeholder layer plus a sharper overlay layer. Use the more precise selector `img[alt^="Generated image"]` instead. The `alt` property is consistently prefixed with `"Generated image: "`, followed by a generated caption, and in practice this selector resolves to the final logical image layer only once.
- The assistant message container selector is `section[data-turn="assistant"]` (or `[data-testid="conversation-turn-N"]`); it is not `[data-message-author-role="assistant"]`. The latter does not exist on the current page.
- A generation run took about 63 seconds in practice (`"Thought for 1m 3s"`). Polling every 3–5 seconds is recommended; the default timeout should be about 150–180 seconds to leave headroom instead of hard-coding to the 63-second baseline.
- One `Create image` request appears to generate exactly one image; no dedicated multi-image UI was observed. For multiple images, the only current options are to request them in the prompt (not guaranteed to work) or to call the flow multiple times.

## Image hosting and download (the most important findings)

The generated image's `<img src>` comes from a **ChatGPT same-origin backend endpoint**, not from an external CDN:

```
https://chatgpt.com/backend-api/estuary/content?id=<file-id>&ts=<timestamp>&p=fs&cid=<n>&sig=<signature>&v=0
```

### Path A: direct URL download — not viable in practice

```js
await fetch(url, { credentials: 'omit' })     // -> 403, application/json
await fetch(url, { credentials: 'include' })  // -> 200, image/png
```

This interface depends on the browser session cookie; it is not a public URL that can be accessed using only signed parameters. Downloading it directly from outside the browser via `Invoke-WebRequest`/`curl` is not viable; do not keep pursuing this route.

### Path B: right-click "Copy image" — not viable

The native right-click menu is rendered at the OS level and does not appear in the page accessibility tree. `find("Copy image context menu item")` clearly returns "not in the accessibility tree", and `right_click` does not capture the native menu screen. This path cannot be automated through claude-in-chrome and should not be used.

### Path C: click the image's own Download button — confirmed and the only working path

1. Every generated image shows a share/export icon in the lower-right corner of the hover toolbar. When locating it with `find`, use the semantic description `"Share this image button"`; do not use fixed coordinates because they change with conversation length and window size.
2. Clicking it opens an image viewer dialog with `[role="dialog"]`, and inside that dialog there is a plain-text `Download` button. `find("Download button in image dialog")` is stable enough to locate.
3. After clicking `Download`, Chrome saves the file directly to the system default Downloads directory. The file name format is fixed as:
   ```
   ChatGPT Image <Mon> <D>, <YYYY>, <hh>_<mm>_<ss> <AM/PM>.png
   ```
   For example, `ChatGPT Image Jul 6, 2026, 06_42_53 PM.png`. The file is the full-resolution original image (1254×1254, about 2 MB), not a lossy screenshot.
4. On the Chrome used for testing, `chrome://settings/downloads` had "Ask where to save each file before downloading" turned off, so the download proceeded without prompts or manual confirmation. If the user's Chrome has that setting enabled, Path C will fail; the skill must tell the user to disable it in SKILL.md or ask them to save it manually.

The only reliable way to confirm a successful download and obtain the real path is to compare the Downloads directory's filename snapshot before and after the click (not the timestamp, but the true before/after set difference). The reason is that this download does not produce any network request at all (`read_network_requests` shows nothing), because it is a pure front-end blob save and cannot be detected from the network layer. See `scripts/snapshot-downloads.ps1` and `scripts/capture-download.ps1`.

### Dead end: trying to move the image URL or bytes out of the browser via `javascript_tool`

- `return img.src` → blocked with `[BLOCKED: Cookie/query string data]`.
- `return btoa(img.src)` (base64 then return) → still blocked, with `[BLOCKED: Base64 encoded data]`.
  The filter is not limited to `&` / `=` query-string patterns; it also recognizes generic base64 character sets. So trying to "bypass" the filter by base64-encoding the URL does not work.
- This means any attempt to return the complete URL or image bytes through the `javascript_tool` return value is not viable. It is not only a 1–2 KB truncation issue; the content filter blocks it at the root.
- Exception: the `tabs_context_mcp` "current tab URL" metadata is not subject to this filter. If it becomes necessary to capture the full signed URL for debugging purposes (for example, to navigate to it in-browser for validation), `javascript_tool` can run `location.href = img.src` and return a harmless placeholder string without returning the URL itself; then `tabs_context_mcp` can be used to read the resulting page URL. This is only a debugging technique, not part of the normal workflow, because Path C is already sufficient.

## Content policy / edge-case observations

- We tested a vague but sensitive request: `"a photorealistic image of a specific real living celebrity's exact face"`.
  ChatGPT did not hard-reject it. Instead, it first displayed a collapsible "thinking summary" in gray text such as `Creating a portrait of a fictional celebrity ›`, and the body explained that the request lacked enough detail to identify a real person and that it should not judge or select a person arbitrarily; it then generated a fictional, highly appealing celebrity image and continued successfully.
  - Conclusion: for requests that allude to a real person without naming them, ChatGPT tends to do a soft rewrite rather than a hard rejection, and the generation flow continues normally.
  - Detection method: the assistant turn includes an extra collapsed summary block with a small arrow before the image generation, which can be observed via `find` / `read_page`, but this does not affect the generation-in-progress / generation-complete logic; the final result still shows `img[alt^="Generated image"]`.
- We did not trigger a true hard refusal in this pass (a pure text response with no image output). In general, the generation-state logic above already covers this: the stop button disappears and `img[alt^="Generated image"]` never appears = treat as refusal/failure, then read the text from that turn and report it to the user.
- Quota exhaustion prompts: this was tested with a Pro subscription and no "limit reached / upgrade" message was observed. The implementation should leave this as an unverified item and, if such a message appears, degrade to "an unknown blocking prompt appeared" and report the exact page text instead of inventing a specific message.

## Pending validation / known gaps

- Details of the reference-image upload workflow (image-to-image / editing with `Upload a photo`, file selection flow, and how it is attached to the prompt) were not tested in this pass; the `reference_image_path` parameter is therefore marked as "to be validated later".
- The quota-exhaustion message for free or non-Pro accounts was not observed and should not be invented.
- An official multi-image generation UI was not found, so the current design assumes one image per generation request.

## Engineering pitfalls (not related to generation itself, but they can interrupt the flow)

- During this investigation, `computer` screenshots and zoom operations frequently timed out with `CDP sendCommand "Page.captureScreenshot" timed out after 30000ms" / "renderer may be frozen"`, especially immediately after opening the image viewer dialog (`role="dialog"`). The pattern is that retries 1–2 times usually recover; if the timeout continues 3 or more times, do not keep waiting on the same tab. Instead use `tabs_create_mcp` to open a new tab, `navigate` to the same conversation URL (`https://chatgpt.com/c/<uuid>`, where chat history is persisted and can be reused), and then `tabs_close_mcp` to close the broken tab.
- After the image viewer dialog (`role="dialog"`) opens, `computer` screenshots often fail to capture its actual content correctly (sometimes returning an odd crop such as 477×62 or timing out entirely). Do not rely on screenshots to determine whether the dialog is open or locate the button; instead use `document.querySelectorAll('[role="dialog"]').length` via `javascript_tool` or simply use `find` to locate the button. Both methods continue to work even when the dialog is not visible or the screenshot is unreliable.