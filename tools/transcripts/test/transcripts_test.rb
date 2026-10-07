# frozen_string_literal: true

# ruby tools/transcripts/test/transcripts_test.rb
# The fixtures are synthetic logs in the shapes Claude Code and Codex write.

require "minitest/autorun"
require "yaml"
require_relative "../lib/draft"

FIXTURES = File.join(__dir__, "fixtures")

class RedactionTest < Minitest::Test
  R = Transcripts::Redaction

  def kinds(text) = R.scan(text).map(&:kind)

  def test_finds_what_must_not_render
    {
      "key sk-ant-api03-#{"a1B2" * 8}" => "secret",
      "token ghp_#{"Ab3" * 12}" => "secret",
      "export ANTHROPIC_API_KEY=abcdefghijklmnop123" => "secret",
      "postgres://user:hunter22@db/x" => "secret",
      "see /Users/someone/dev/x.py" => "path",
      "in ~/vault/fieldwork/note.md" => "path",
      "open obsidian://open?vault=x" => "path",
      "host box.tail1a2b3.ts.net" => "host",
      "ssh examplehost" => "host",
      "on examplehost-2 again" => "host",
      "at 100.101.2.3" => "address",
      "mail someone@example.org" => "email",
      "blob Zm9vYmFyQmF6UXV4MTIzNDU2Nzg5MEFCQ0RFRkdISUpL" => "secret"
    }.each { |text, kind| assert_includes kinds(text), kind, text }
  end

  def test_leaves_ordinary_text_alone
    [
      "commit 8cc54ba and sha256 c290090d6391829bb7c1571f3460f90bcbf28331e11e2051faa80f5b90dc8c45",
      "session 019f81fa-31ad-7980-b2cd-5ccf743612e8",
      "see ecological-network-math/reports/lv-six-cycle-paper/THEOREM-BOUNDARY.md",
      "write to caleb@polli.ai",
      "the sixth cycle sits at a = 0.31, b = 1/7",
      "[redacted path] and [redacted host]"
    ].each { |text| assert_empty R.scan(text), text }
  end

  def test_redact_replaces_in_place
    assert_equal "ran [redacted path] on [redacted host] with [redacted secret]",
                 R.redact("ran /Users/someone/x.sh on examplehost with sk-#{"Zz9" * 9}")
  end

  def test_allow_list
    assert_empty R.scan("ssh examplehost", allow: ["examplehost"])
  end
end

class ClaudeCodeAdapterTest < Minitest::Test
  def setup
    @s = Transcripts::Adapters::ClaudeCode.read(File.join(FIXTURES, "claude-code.jsonl"))
  end

  def test_keeps_only_what_people_and_the_agent_said
    assert_equal "haaha".chars, @s.messages.map(&:role)
    assert_equal "Good. Certify it.", @s.messages[3].text
    assert_equal %w[typed typed], @s.messages.select { |m| m.role == "h" }.map(&:origin)
  end

  def test_joins_split_records_and_keeps_reasoning
    assert_equal "I'll start from the five-cycle system.", @s.messages[1].text
    assert_equal "Start from the five-cycle system.", @s.messages[1].reasoning
  end

  def test_ledger_facts
    assert_equal 1, @s.tool_calls
    assert_equal ["claude-opus-4-9"], @s.models
    assert_in_delta 3.14, @s.cost["usd"]
    assert_equal 60, @s.tokens["input_tokens"]
    assert_equal "2026-08-10T18:00:00Z", @s.started.iso8601
  end
end

class CodexAdapterTest < Minitest::Test
  def setup
    @s = Transcripts::Adapters::Codex.read(File.join(FIXTURES, "codex.jsonl"))
  end

  def test_human_messages_drop_injected_context_and_heartbeats
    humans = @s.messages.select { |m| m.role == "h" }
    assert_equal ["[attached: plot.png]\nTry the Rohr family at S = 5."], humans.map(&:text)
  end

  def test_agent_messages_reasoning_and_tools
    assert_equal "haa".chars, @s.messages.map(&:role)
    assert_equal "**Choosing a witness search**", @s.messages[1].reasoning
    assert_equal 2, @s.tool_calls
    assert_nil @s.cost
    assert_equal 1000, @s.tokens["input_tokens"]
    assert_equal ["gpt-6-sol"], @s.models
  end
end

class DigestTest < Minitest::Test
  D = Transcripts::Digest

  def draft
    s = Transcripts::Adapters::ClaudeCode.read(File.join(FIXTURES, "claude-code.jsonl"))
    YAML.safe_load(YAML.dump(Transcripts::Draft.build(s, work: { id: "note/x", title: "X" })))
  end

  def curated
    d = draft
    d["title"] = "Six cycles"
    d["status"] = "approved"
    d["approval"] = { "by" => "Caleb", "date" => "2026-10-08" }
    d["chapters"][0]["title"] = "“Can the class 27 family carry a sixth cycle?”"
    d["chapters"][0]["turns"].each { |t| t["text"] = "Checked the fold." if t["role"] == "agent" }
    d
  end

  def test_draft_redacts_and_is_refused_without_preview
    d = draft
    assert_includes d["chapters"][0]["turns"][0]["text"], "[redacted path]"
    errors = D.validate("x", d)
    assert(errors.any? { |e| e.include?("is a draft") })
    assert(errors.any? { |e| e.include?("placeholder") })
    assert_empty D.validate("x", d, drafts_allowed: true).grep(/redact|secret|path|host/)
  end

  def test_curated_digest_passes_and_derives
    d = curated
    assert_empty D.validate("x", d)
    x = D.derive("x", d)
    assert_equal "1 h 45 min", x["wall"]
    assert_equal "14:00", x["chapters"][0]["turns"][0]["clock"]
    assert_equal "1 h 10 min", x["chapters"][0]["turns"][2]["gap"]
    assert_includes x["preface"].join(" "), "4 of the session’s 5 messages are shown"
    assert_includes x["preface"].join(" "), "(two places)"
    assert_equal "$3.14 at API prices, as reported by Claude Code", x["cost"]
    assert_equal [1, nil, 1, 1, 1], x["strip"].map { |c| c["chapter"] }
  end

  def test_rules_are_checked_against_the_turns
    d = curated
    d["chapters"][0]["turns"][1]["mode"] = "verbatim"
    assert(D.validate("x", d).any? { |e| e.include?("mode must be summary") })

    d = curated
    d["chapters"][0]["turns"][0]["msg"] = 2
    assert(D.validate("x", d).any? { |e| e.include?("is agent, not human") })

    d = curated
    d["editing"].delete("tools-omitted")
    assert(D.validate("x", d).any? { |e| e.include?("tools-omitted") })

    d = curated
    d["chapters"][0]["turns"][1]["excerpt"]["text"] = "ran it on examplehost"
    assert(D.validate("x", d).any? { |e| e.include?("host at chapters.0.turns.1.excerpt.text") })
  end
end
