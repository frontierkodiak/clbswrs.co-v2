# Stream implementation and handoff (PL-313)

The public home page and its navigation remain unchanged. `/stream/` mixes
literal-text notes, quotations, links and one-line references to existing art.
There are no invented posts or imported highlights.

## Posting route

The implementation uses signed, token-free iOS Shortcuts plus a client-only
publisher at `/stream/post/`. The Shortcut reads Safari's selected text, title,
URL and optional author metadata, then opens a URL fragment (not a query string).
The publisher strips the fragment from browser history and sends one Contents
API PUT to `frontierkodiak/clbswrs.co-v2@gh-pages`.

This differs from the issue's recommended native-only API Shortcut: the token
is stored once on the site's origin, not copied into multiple Shortcuts, and
literal-text serialization, retry recovery and error reporting have executable
browser tests. There is no server, subscription or model. A per-phone random
pairing key is appended by a **native Text action**, never passed to a source
webpage's JavaScript. Without that key, a shared URL cannot auto-post using the
browser's stored token. Manual posting always requires tapping Post.

Safari's selected-text path is designed for Share → Quote to stream after
one-time permissions and pairing. It has **not been timed on Caleb's phone**.
The optional reaction composer requires a Post tap. Non-Safari news apps have a
manual fallback because their selected-text/title/URL payloads are not uniform;
the issue's universal two-tap news-app requirement is **not fulfilled yet**.
Establish which app Caleb actually uses before claiming it works there.

The browser token has Contents write access to one repository (GitHub cannot
scope a Contents token to just `_stream/`). It is never sent to the source site,
included in a post, or included in a Shortcut. The posting page loads only
first-party scripts and permits connections only to itself and api.github.com.

Official references: [Apple's Safari JavaScript input contract](https://support.apple.com/guide/shortcuts/intro-to-the-run-javascript-on-webpage-action-apd218e2187d/ios),
[GitHub's create-file API](https://docs.github.com/en/rest/repos/contents#create-or-update-file-contents),
[fine-grained token setup](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens).

## Files and dates

`_stream/*.md` contains JSON front matter (valid YAML) and an empty body. Each
file holds `kind`, `date`, literal `text`, optional `title`, `reaction`,
`source_title`, `source_url`, `source_author`, `tags` and `date_source`. It is
rendered with HTML escaping and pre-wrapped whitespace, **not** Markdown or
Liquid evaluation. An untitled note remains untitled on the page; Atom uses an
excerpt as its required entry title.

Device timestamps are formatted in America/New_York with their explicit UTC
offset; the provenance says they come from the device clock. Existing art
entries use the first-addition commit `521080851cf488ae0c0e78cd1adc16827a558ca1`,
2023-12-26T23:25:31-05:00, not a fabricated day in 2018 or 2020. Their artwork
date ranges are copied from the existing pages and labelled separately.

Later research notes and timeline cards can add `_stream/` reference files with
`kind: research` or `kind: timeline`, a provided `title`, `target_url`, verified
`date`, `date_source`, optional `date_source_url`, `date_label` and `tags`. Do not
backdate a reflection; its publication date is when it is written/published.

## Rebuild Shortcuts

On macOS, without any personal token:

```sh
python3 tools/build-shortcuts.py
shortcuts sign --mode anyone --input tools/unsigned-shortcuts/quote-to-stream.shortcut --output assets/shortcuts/quote-to-stream.shortcut
```

Repeat the signing command for `quote-with-reaction`, `note-to-stream` and
`share-to-stream`. Signing verifies the installable envelope, **not** runtime
behaviour on iOS. The files use standard Shortcuts plist action identifiers;
the native runtime refused schema introspection outside Apple's platform binary.
Phone import/run remains a required acceptance check.

## Verification

```sh
node --test tests/publisher.test.mjs
make check
bundle exec ruby tests/stream-rendering.rb
```

The rendering check builds a temporary source with synthetic adversarial text,
checks literal HTML/Atom/plain-text output and removes its temporary build. It
never adds demonstration posts to the production collection. Browser checks
mock api.github.com; they do not claim a real Caleb post or real PAT write.

For the browser smoke, serve `_site/` on localhost:4313 and open a managed
Playwright CLI session named `stream-check` at `/stream/post/`, then run:

```sh
node -e 'require("node:child_process").execFileSync("playwright-cli", ["-s=stream-check", "run-code", require("node:fs").readFileSync("tests/browser-smoke.js", "utf8")], {stdio: "inherit"})'
```

Close the browser and local server after testing. The smoke checks unpaired
shares, automatic paired posting, same-tab hash navigation, exact text and
retry identity across a reload. Its only token is synthetic.

The W3C feedvalidator at `9ce274c9db93796b8ab2a44952b9da80811bf765`
reported zero errors for the generated Atom feed (checked with its live URL as
the base). It warns about the three art entries' identical `updated` times;
those timestamps deliberately retain their shared first-addition Git receipt.

## Deferred importers — do not build before habitual posting

- **X bookmarks:** read the existing archive/API route, keep native item IDs and
  actual saved timestamps, deduplicate by item ID. Bookmarks are not quote-tweet
  authorship; retain source URLs and distinguish saved from published time.
- **Zotero additions:** read his selected collection with Zotero's API, persist
  item keys and sync-version cursor, use `dateAdded` as a saved timestamp. Ask
  which collections should be public before emitting references.
- **GitHub releases:** poll the chosen repositories' release IDs/published times,
  retain a cursor, emit links once per release. No rewriting release text.
- **Old X quote-tweets:** wait for Caleb's X data export; parse native tweet IDs,
  timestamps, quoted-tweet/source links and his exact commentary. Recover missing
  quoted text only from a cited source, with gaps labelled. Never manufacture it.
- **Highlights:** the source is still unknown (WSJ, Safari, Kindle, screenshots).
  An importer needs an actual export/API/share payload and permission to publish
  each selection. This is distinct from making the share path work today.
