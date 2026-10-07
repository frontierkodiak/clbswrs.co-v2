---
layout: default
title: Stream — phone setup
permalink: /stream/install/
robots: noindex, nofollow
---
# Phone setup

1. In GitHub, [create a fine-grained token](https://github.com/settings/personal-access-tokens/new). Resource owner: **frontierkodiak**. Repository access: **Only select repositories → clbswrs.co-v2**. Repository permissions: **Contents → Read and write**. Leave the other permissions unchanged. Choose an expiry you will remember.
2. In **Safari**, open [Post to stream](/stream/post/). Under **Phone setup**, paste the token and tap **Save on this phone**. It stays in this Safari browser's storage; no agent receives it. Do not use Private Browsing.
3. Tap **Pair two-tap quotations** and copy the displayed pairing key. Open the quotation Shortcuts below, tap **Add Shortcut**, and paste that key when asked. Both quotation Shortcuts use the same key. Pin **Quote to stream** near the top of Safari's share sheet.
4. In Settings → Apps → Shortcuts → Advanced, enable **Allow Running Scripts** if it is off. On the first run, allow the Shortcut to run JavaScript on the selected webpage. These are one-time setup prompts, not part of the routine two taps.

## Install

- [Quote to stream](/assets/shortcuts/quote-to-stream.shortcut) — Safari: select text → Share → **Quote to stream**. It posts immediately, with the page title, URL and any author metadata the page provides. **No Post button.** Its routine path is the two share-sheet taps; this still needs verification on your phone.
- [Quote with reaction](/assets/shortcuts/quote-with-reaction.shortcut) — the same selection and source, opened in the composer. Add a reaction, name or tags, then tap **Post**. This optional path takes an extra tap.
- [Note to stream](/assets/shortcuts/note-to-stream.shortcut) — add it to the Home Screen or an Action Button. Opens a blank note composer; type or dictate and tap **Post**. Titles and tags are optional.
- [Share to stream](/assets/shortcuts/share-to-stream.shortcut) — for other apps sharing text or URLs. It opens a draft, **not an automatic post**. Check the app's shared text and supply any missing source title or URL. Universal two-tap posting from news apps is not established; their share payloads differ.

Sharing a Safari page with **no selection** opens a link draft instead of quoting the whole article. Your text, line breaks and punctuation are stored as entered. No LLM or backend service is involved. The publisher commits one file to `gh-pages`; GitHub Pages builds it, normally in a few minutes. A commit receipt is not a claim that the site is already live.

## Edit or delete

After posting, the receipt links to the source file on GitHub. Open it in GitHub mobile (or Safari), edit its `text`, `reaction` or other fields, then commit to `gh-pages`. For an edit, add `updated` with the current ISO timestamp and leave `date` unchanged. To remove it, use **Delete file**, then commit. The next Pages build updates the stream, permalink, Atom and plain-text feed together. Git history retains deleted text; deleting a file does not erase its history.

If posting fails, the draft and its exact file ID stay on the phone. **Retry same post** verifies a possibly successful commit instead of making a duplicate. **Discard draft** clears the local draft, not a file already committed. **Forget access** removes the token and pairing key from this browser. Clearing Safari website data also removes them; pair the Shortcuts again after setting up another browser or phone.

First acceptance check: install, share one real sentence, then check [the stream](/stream/) after the Pages build. The installation and first real post must be done by Caleb.
