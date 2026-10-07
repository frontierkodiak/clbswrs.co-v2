# Transcript digests

A digest is a curated record of one AI session that produced something on the
site: the person's words verbatim, the agent's replies cut to one-line italic
summaries, chapters titled by a line from the session, and a ledger of what
was left out. One YAML file per session lives in `_data/transcripts/`.

## From a raw log to a page

1. **Draft.** An adapter reads the raw log and writes a draft with every
   human message and, after each, the agent's last reply as a verbatim
   excerpt. Redaction runs as it writes. Drafts go to `.transcripts/drafts/`,
   which neither git nor Jekyll reads.

   ```sh
   tools/transcripts/draft claude-code ~/.claude/projects/<project>/<session>.jsonl --id <id>
   tools/transcripts/draft codex ~/.codex/sessions/<y>/<m>/<d>/rollout-<…>.jsonl --id <id> \
     --work-id note/<slug> --work-title "<title>"
   ```

   Adapters exist for Claude Code and Codex. ChatGPT, Claude.ai and AI Studio
   exports are next (formats in the AI usage history archive).

2. **Curate.** Cut turns, split into chapters, write each agent summary,
   mark any shortened human turn `mode: condensed`. A draft is a proposal for
   Caleb's selection, never a publish.

3. **Approve.** Caleb chooses the turns and approves his words. Then set
   `status: approved` and `approval: {by: Caleb, date: …}`, and move the file
   to `_data/transcripts/<id>.yml`.

4. **Place.** A page with `layout: transcript` and `digest: <id>` renders it.
   A work item links to it with
   `{% include transcript-line.html work="<work id>" %}`, which prints
   "The making of this: 1 session, conversation →".

`tools/transcripts/check [--drafts FILE…]` runs the same checks as the build.
`TRANSCRIPT_DRAFTS=1 make serve` previews drafts locally; without it the build
refuses any digest that isn't approved.

## The build gate

`_plugins/transcripts.rb` runs after Jekyll reads the site and before it
renders anything. It fails the build if a digest:

- contains a secret or token, a private path (`/Users`, `~/`, `/mango`, …),
  a fleet host name, a tailnet name or address, a private IP or an email
  address, anywhere in the file, rendered or not;
- is a draft, or still holds a `TODO` placeholder;
- claims an editing rule its turns break, or points a turn at a message of
  the wrong role.

A phrase that is a false positive goes in `redaction.allow` with the digest,
where the reviewer sees it.

## Format

```yaml
title: Finding the sixth cycle
status: approved                       # draft | approved
approval: {by: Caleb, date: 2026-10-09}
work:                                  # the work item it belongs to
  id: note/lv-six-cycles
  title: Six limit cycles in a three-dimensional Lotka–Volterra system
  url: /notes/lv-six-cycles/           # once the work is published
names: {human: Caleb, agent: Codex}
source:                                # written by the adapter, from the log
  harness: codex                       # claude-code | codex | chatgpt | claude-ai | ai-studio
  harness_version: 0.150.0
  models: [gpt-6-sol]
  session: 019f81fa-31ad-7980-b2cd-5ccf743612e8
  started: '2026-08-10T18:00:00Z'
  ended: '2026-08-10T23:38:00Z'
  timezone: {name: US Eastern, offset: '-04:00'}
  locator: {archive: agent-session-archive, sha256: …, bytes: …}   # never rendered
  counts: {human: 12, agent: 140, tool_calls: 431}
  sequence: haaaah…                    # one letter per message, h human, a agent
  cost: {usd: 15.98, basis: at API prices, as reported by Claude Code}   # absent: "cost not reported"
editing: [human-verbatim, agent-summarised, tools-omitted, turns-selected, redacted]
redaction: {allow: []}
chapters:
  - title: "“Can it carry a sixth?”"   # a line from the session
    turns:
      - role: human                    # human | agent
        mode: verbatim                 # human: verbatim | condensed; agent: summary
        msg: 1                         # position in source.sequence
        at: '2026-08-10T18:00:00Z'
        text: …
      - role: agent
        mode: summary
        msg: 7
        at: '2026-08-10T18:31:00Z'
        text: Ran the continuation from the five-cycle system and found a fold.
        excerpt: {label: its reasoning, text: …}   # optional, verbatim
summary: One closing sentence.         # optional
```

The "How to read this" preface, the ledger, the clock times and the message
strip are computed from these fields at build time. Nothing in them is typed
by hand, so they can't disagree with the turns.

The locator finds the raw log in the fleet session archive by content hash;
it names no host or path. Times are UTC in the file and shown in the
digest's time zone.
