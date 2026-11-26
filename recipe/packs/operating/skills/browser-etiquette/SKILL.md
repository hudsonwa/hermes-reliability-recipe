---
name: browser-etiquette
version: 0.3.0
description: "Use before any browser task: one session, navigate like a person, repair in place, read back form entries, CAPTCHA policy, final clicks need a yes."
author: hermes-reliability-recipe operating pack
platforms: [macos, linux]
metadata:
  hermes:
    tags: [browser, reliability, safety]
---

# Browser etiquette

Your SOUL's hard rules win over this skill. A site-specific skill of yours (its documented URLs, login flow, routes) wins over the general habits below, but never over a hard rule.

## Session
- One browser session per task. The first load may go straight to a URL; after that, use the
  site's own links, menus and buttons to move around.
- Do not close and relaunch the browser to recover or to land on a page. Relaunch only after a
  real crash, and log why.
- Do not bring windows to the front over the owner's work, and do not drive the owner's own
  browser or other apps unless your SOUL allows it.

## When something goes wrong
1. Read the page (snapshot / screenshot) before acting again.
2. Say what is actually on screen: error, login wall, different layout, still loading.
3. Adjust (wait, scroll, pick the right element) and retry in the same page.
4. After three failed tries on the same step, stop and report what you saw and what you tried.
Write each adjustment in your log as `adapt: before → after`.

## Reading state
- The page's own status is the truth only after a fresh load. A list view can lag behind the
  item page; read the item itself.
- A screenshot can lag one tool-round behind the live page (and `vision_analyze` reads whatever
  image its path held when it ran). For field values, prefer reading the DOM over a screenshot;
  when using screenshots to verify a state change, take the shot in the same call as the action
  or immediately re-shoot before analysing.
- Before continuing saved work (drafts, half-filled forms), load it read-only and note what is
  already there. Never retype over saved answers.

## Frames, widgets and shadow DOM
- `page_info`/`js` see only the light DOM plus shadow roots you walk explicitly. Forms inside
  shadow DOM or cross-origin iframes need the same treatment: recurse `shadowRoot` for elements,
  and `iframe.getBoundingClientRect()` for click geometry.
- Synthetic JS clicks and programmatic value sets (`el.value = x` + input event) often do not
  reach framework components (LWC/Aura/shadow) or cross-origin widget iframes - the screen shows
  the value but the component state stays empty. Prefer real input events: `fill_input` where it
  works, otherwise `cdp('Input.dispatchKeyEvent', type='char', text=ch)` per character with the
  field focused, and re-read the DOM value to confirm it landed.

## Forms
- Confirm you are on the right form for the right entity and period before typing.
- After entering a field, read it back. Keep a record of what you entered and from which source.
- Leave the final submit / sign / declare / pay / send click to the owner unless they said yes
  to that exact action in this conversation.

## Never
{{CAPTCHA_POLICY_SKILL}}
- Never try to hide automation or get round bot checks, rate limits or access controls.
- Never type a password or card number yourself; the owner or a vault does that. Use a one-time
  code only where one of your own skills documents that the owner set up that exact flow.
