# clbswrs.co

Source for Caleb Sowers's personal site at [clbswrs.co](https://clbswrs.co).
The site is intentionally small: Jekyll renders Markdown, Liquid templates, and
the local console-style theme into static files for GitHub Pages.

## Requirements

- Ruby 3.4.10, selected through `.ruby-version`
- Bundler 2.6 or newer

With `rbenv`, make sure its shims are on `PATH`, then run:

```sh
rbenv install --skip-existing 3.4.10
make setup
```

## Local development

```sh
make serve
```

Jekyll serves the site at `http://127.0.0.1:4000`. The server reloads when
source files change.

## Verification

```sh
make check
```

The check builds the production site and validates the generated HTML, internal
links, images, and scripts. External links are deliberately excluded from this
deterministic gate and can be audited separately.

## Deployment

The `gh-pages` branch is the production source. Pull requests run the same build
and validation as production. After the repository's Pages source is switched
to **GitHub Actions**, pushes to `gh-pages` build an artifact and deploy it to the
protected `github-pages` environment. The custom domain remains configured as
`clbswrs.co` in both the repository settings and `CNAME`.

Do not commit `_site`, Bundler caches, Jekyll caches, or operating-system
metadata. Do not delete apparently unused art assets without a separate content
and archival review.

The visual foundation originated with
[jekyll-theme-console](https://github.com/b2a3e8/jekyll-theme-console) and remains
available under the [MIT License](LICENSE.txt).

## Stream

The mixed stream lives at `/stream/`, with Atom at `/stream/atom.xml` and literal
plain text at `/llms-full.txt`. Phone setup and signed Shortcuts are at
`/stream/install/`. See [the implementation and acceptance handoff](docs/stream.md)
for the file contract, retry behaviour, verification and remaining phone checks.
