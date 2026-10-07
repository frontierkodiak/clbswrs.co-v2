# frozen_string_literal: true

require "yaml"
require_relative "digest"
require_relative "redaction"
require_relative "adapters/claude_code"
require_relative "adapters/codex"

module Transcripts
  # Turns a Session into a draft digest: every human message verbatim, and
  # after each one the agent's last reply as a verbatim excerpt waiting for a
  # one-line summary. A draft is a proposal for Caleb to cut down; the build
  # refuses to publish it.
  module Draft
    ADAPTERS = { "claude-code" => Adapters::ClaudeCode, "codex" => Adapters::Codex }.freeze

    module_function

    def read(harness, path)
      adapter = ADAPTERS.fetch(harness) { raise ArgumentError, "no adapter for #{harness}; have #{ADAPTERS.keys.join(", ")}" }
      adapter.read(path)
    end

    def build(session, work: {}, human: "Caleb", zone: "US Eastern", tz: "America/New_York", all: false)
      seq = session.messages.map(&:role).join
      offset = utc_offset(session.started, tz)
      turns = []
      session.messages.each_with_index do |m, i|
        nxt = session.messages[i + 1]
        if m.role == "h"
          turns << {
            "role" => "human", "mode" => "verbatim", "msg" => i + 1, "at" => iso(m.at),
            "origin" => m.origin, "text" => clean(m.text)
          }
        elsif all || nxt.nil? || nxt.role == "h"
          turn = {
            "role" => "agent", "mode" => "summary", "msg" => i + 1, "at" => iso(m.at),
            "text" => "TODO: one line, past tense",
            "excerpt" => { "label" => "reply", "text" => clean(m.text) }
          }
          turn["reasoning"] = clean(m.reasoning) if m.reasoning
          turns << turn
        end
      end

      {
        "title" => "TODO",
        "status" => "draft",
        "work" => { "id" => work[:id] || "TODO", "title" => work[:title] || "TODO" },
        "names" => { "human" => human, "agent" => Digest::HARNESSES[session.harness] },
        "source" => {
          "harness" => session.harness,
          "harness_version" => session.harness_version,
          "models" => session.models,
          "session" => session.session,
          "started" => iso(session.started),
          "ended" => iso(session.ended),
          "timezone" => { "name" => zone, "offset" => offset },
          "locator" => { "archive" => "agent-session-archive", "sha256" => session.sha256, "bytes" => session.bytes },
          "counts" => { "human" => seq.count("h"), "agent" => seq.count("a"), "tool_calls" => session.tool_calls },
          "sequence" => seq,
          "cost" => session.cost,
          "tokens" => session.tokens
        }.compact,
        "editing" => Digest::RULES.dup,
        "redaction" => { "allow" => [] },
        "chapters" => [{ "title" => "TODO: a line from the session", "turns" => turns }]
      }
    end

    def to_yaml(digest, session, id:)
      header = <<~TXT
        # DRAFT transcript digest #{id}. Not for publication until Caleb picks
        # the turns and approves his words. Cut turns, split into chapters titled
        # by a line from the session, write each agent summary, then set
        # status: approved with approval.by and approval.date.
        # Drafted #{Time.now.utc.strftime("%Y-%m-%d")} by tools/transcripts/draft from a #{session.harness} log.
      TXT
      warnings = session.warnings.map { |w| "# WARNING: #{w}\n" }.join
      header + warnings + YAML.dump(digest, line_width: -1).sub(/\A---\n/, "")
    end

    def clean(text)
      Redaction.redact(text.to_s.gsub("\r\n", "\n").strip)
    end

    def iso(time)
      time&.utc&.iso8601
    end

    def utc_offset(time, tz)
      return "+00:00" unless time

      old = ENV["TZ"]
      ENV["TZ"] = tz
      time.getlocal.strftime("%:z")
    ensure
      ENV["TZ"] = old
    end
  end
end
