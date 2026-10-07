# frozen_string_literal: true

require "date"
require "time"
require_relative "redaction"

module Transcripts
  # A digest is one curated transcript: `_data/transcripts/<id>.yml`.
  # `validate` lists everything wrong with one; `derive` computes what the
  # include prints (preface, ledger, clock times, the message strip) so that
  # none of it is typed by hand and none of it can drift from the turns.
  # The format is described in tools/transcripts/README.md.
  module Digest
    HARNESSES = {
      "claude-code" => "Claude Code", "codex" => "Codex", "chatgpt" => "ChatGPT",
      "claude-ai" => "Claude.ai", "ai-studio" => "AI Studio"
    }.freeze
    ROLES = %w[human agent].freeze
    MODES = { "human" => %w[verbatim condensed], "agent" => %w[summary] }.freeze
    RULES = %w[human-verbatim agent-summarised tools-omitted turns-selected redacted].freeze
    STATUSES = %w[draft approved].freeze
    REDACTION_MARK = /\[redacted (?:secret|path|host|address|email)\]/
    PLACEHOLDER = /\A\s*(?:TODO|TBD|FIXME)\b/

    module_function

    def turns(data)
      Array(data["chapters"]).flat_map { |c| Array(c["turns"]) }
    end

    def validate(id, data, drafts_allowed: false)
      errors = []
      err = ->(msg) { errors << "#{id}: #{msg}" }
      return ["#{id}: not a mapping"] unless data.is_a?(Hash)

      err.("title is missing") if blank?(data["title"])
      unless STATUSES.include?(data["status"])
        err.("status must be one of #{STATUSES.join(", ")}")
      end
      if data["status"] == "draft" && !drafts_allowed
        err.("is a draft; drafts render only with TRANSCRIPT_DRAFTS=1 and are never published")
      end
      if data["status"] == "approved" && blank?(data.dig("approval", "by"))
        err.("approved digests record approval.by and approval.date")
      end

      work = data["work"] || {}
      err.("work.id and work.title are required") if blank?(work["id"]) || blank?(work["title"])

      src = data["source"] || {}
      err.("source.harness must be one of #{HARNESSES.keys.join(", ")}") unless HARNESSES.key?(src["harness"])
      %w[session started ended].each { |k| err.("source.#{k} is required") if blank?(src[k]) }
      err.("source.models needs at least one model") if Array(src["models"]).empty?
      %w[started ended].each do |k|
        Time.iso8601(src[k].to_s)
      rescue ArgumentError
        err.("source.#{k} is not an ISO 8601 time")
      end
      seq = src["sequence"].to_s
      err.("source.sequence must be h/a letters, one per message") unless seq.match?(/\A[ha]+\z/)

      rules = Array(data["editing"])
      (rules - RULES).each { |r| err.("unknown editing rule #{r.inspect}") }

      chapters = Array(data["chapters"])
      err.("needs at least one chapter") if chapters.empty?
      seen = {}
      chapters.each_with_index do |ch, ci|
        err.("chapter #{ci + 1} has no title") if blank?(ch["title"])
        Array(ch["turns"]).each_with_index do |t, ti|
          at = "chapter #{ci + 1}, turn #{ti + 1}"
          role, mode = t["role"], t["mode"]
          next err.("#{at}: role must be human or agent") unless ROLES.include?(role)

          unless MODES[role].include?(mode)
            err.("#{at}: a #{role} turn's mode must be #{MODES[role].join(" or ")}")
          end
          err.("#{at}: text is empty") if blank?(t["text"])
          err.("#{at}: text is a placeholder") if !drafts_allowed && t["text"].to_s.match?(PLACEHOLDER)
          if t["excerpt"] && blank?(t.dig("excerpt", "text"))
            err.("#{at}: excerpt has no text")
          end
          n = t["msg"]
          if !n.is_a?(Integer) || n < 1 || n > seq.length
            err.("#{at}: msg must point into source.sequence (1..#{seq.length})")
          elsif seq[n - 1] != role[0]
            err.("#{at}: message #{n} in the session is #{seq[n - 1] == "h" ? "human" : "agent"}, not #{role}")
          elsif seen[n]
            err.("#{at}: message #{n} is already shown at #{seen[n]}")
          else
            seen[n] = at
          end
          begin
            Time.iso8601(t["at"].to_s)
          rescue ArgumentError
            err.("#{at}: at is not an ISO 8601 time")
          end
        end
      end

      ns = turns(data).map { |t| t["msg"] }.grep(Integer)
      err.("turns are not in session order") unless ns == ns.sort

      # Every rule that is claimed must be true of the turns.
      ts = turns(data)
      if rules.include?("human-verbatim") && ts.any? { |t| t["role"] == "human" && !MODES["human"].include?(t["mode"]) }
        err.("claims human-verbatim, but a human turn is neither verbatim nor marked condensed")
      end
      if rules.include?("agent-summarised") && ts.any? { |t| t["role"] == "agent" && t["mode"] != "summary" }
        err.("claims agent-summarised, but an agent turn is not a summary")
      end
      (RULES - rules).each { |r| err.("must state the editing rule #{r}") }

      allow = Array(data.dig("redaction", "allow"))
      Redaction.scan_tree(data, allow: allow) do |f|
        next if f.where.start_with?("redaction.allow")

        err.("#{f.kind} at #{f.where}: #{f.preview}")
      end
      errors
    end

    # Fields the include prints. Everything here is computed from the digest.
    def derive(id, data, url: nil)
      src = data["source"]
      names = data["names"] || {}
      human = names["human"] || "Caleb"
      agent = names["agent"] || HARNESSES[src["harness"]]
      offset = src.dig("timezone", "offset") || "+00:00"
      zone = src.dig("timezone", "name") || "UTC"
      started = Time.iso8601(src["started"]).getlocal(offset)
      ended = Time.iso8601(src["ended"]).getlocal(offset)
      seq = src["sequence"]
      ts = turns(data)

      counts = {
        "messages" => seq.length,
        "human_messages" => seq.count("h"),
        "agent_messages" => seq.count("a"),
        "shown" => ts.length,
        "human_shown" => ts.count { |t| t["role"] == "human" },
        "condensed" => ts.count { |t| t["mode"] == "condensed" },
        "agent_shown" => ts.count { |t| t["role"] == "agent" },
        "excerpts" => ts.count { |t| t["excerpt"] },
        "redactions" => strings(data).sum { |s| s.scan(REDACTION_MARK).length },
        "tool_calls" => src.dig("counts", "tool_calls")
      }

      chapters = Array(data["chapters"]).each_with_index.map do |ch, ci|
        prev = nil
        turns = Array(ch["turns"]).each_with_index.map do |t, ti|
          at = Time.iso8601(t["at"]).getlocal(offset)
          gap = prev ? ((at - prev) / 60).round : nil
          prev = at
          {
            "anchor" => "t#{ci + 1}-#{ti + 1}",
            "clock" => at.strftime("%H:%M"),
            "elapsed" => duration(at - started, clock: true),
            "gap" => gap && gap >= 45 ? duration(gap * 60) : nil
          }
        end
        { "number" => ci + 1, "anchor" => "c#{ci + 1}", "turns" => turns }
      end

      shown = {}
      Array(data["chapters"]).each_with_index do |ch, ci|
        Array(ch["turns"]).each_with_index { |t, ti| shown[t["msg"]] = [ci + 1, "t#{ci + 1}-#{ti + 1}"] }
      end
      strip = seq.chars.each_with_index.map do |k, i|
        ch, anchor = shown[i + 1]
        { "k" => k, "chapter" => ch, "anchor" => anchor }
      end

      wall = duration(ended - started)
      day = started.strftime("%-d %b %Y")
      span = started.to_date == ended.to_date ? "#{started.strftime("%H:%M")}–#{ended.strftime("%H:%M")}" :
                                                 "to #{ended.strftime("%-d %b %H:%M")}"
      cost = src["cost"]
      cost_text = if cost && cost["usd"]
                    "$#{format("%.2f", cost["usd"])} #{cost["basis"]}".strip
                  else
                    "cost not reported"
                  end

      {
        "id" => id,
        "url" => url,
        "human" => human,
        "agent" => agent,
        "harness" => HARNESSES[src["harness"]],
        "models" => Array(src["models"]).join(", "),
        "date" => day,
        "span" => span,
        "zone" => zone,
        "wall" => wall,
        "cost" => cost_text,
        "counts" => counts,
        "preface" => preface(data, counts, human, agent),
        "ledger" => [
          "1 session",
          "#{day}, #{span} #{zone}",
          wall,
          "#{counts["shown"]} of #{counts["messages"]} messages shown",
          counts["tool_calls"] ? "#{counts["tool_calls"]} tool calls left out" : nil,
          cost_text
        ].compact,
        "chapters" => chapters,
        "strip" => strip,
        "draft" => data["status"] != "approved"
      }
    end

    def preface(data, c, human, agent)
      rules = Array(data["editing"])
      lines = []
      if rules.include?("human-verbatim")
        lines << if c["condensed"].positive?
                   "#{human}’s messages are verbatim, except #{count(c["condensed"], "one", "ones")} marked " \
                     "<em>condensed</em>, which #{c["condensed"] == 1 ? "is" : "are"} shortened."
                 else
                   "#{human}’s messages are verbatim."
                 end
      end
      if rules.include?("agent-summarised")
        s = "#{agent}’s replies are replaced by <em>one-line italic summaries</em>, written afterwards"
        s += c["excerpts"].positive? ? "; #{count(c["excerpts"], "opens", "open")} to the verbatim text." : "."
        lines << s
      end
      lines << "Commands, file edits and their output are left out." if rules.include?("tools-omitted")
      if rules.include?("turns-selected")
        lines << "#{c["shown"]} of the session’s #{c["messages"]} messages are shown " \
                 "(#{c["human_shown"]} of #{c["human_messages"]} of #{human}’s)."
      end
      if rules.include?("redacted")
        lines << if c["redactions"].positive?
                   "Keys, private paths and machine names are replaced by <span class=\"tx-redacted\">[redacted]</span> " \
                     "(#{count(c["redactions"], "place", "places")})."
                 else
                   "Nothing needed redacting."
                 end
      end
      lines
    end

    def count(n, one, many)
      words = %w[zero one two three four five six seven eight nine ten]
      num = n <= 10 ? words[n] : n.to_s
      if n == 1
        one == "one" ? "one" : "one #{one}"
      else
        many == "ones" ? num : "#{num} #{many}"
      end
    end

    def duration(seconds, clock: false)
      mins = (seconds / 60.0).round
      h, m = mins.divmod(60)
      return format("%d:%02d", h, m) if clock
      return "#{m} min" if h.zero?

      m.zero? ? "#{h} h" : "#{h} h #{m} min"
    end

    def strings(node, acc = [])
      case node
      when Hash then node.each_value { |v| strings(v, acc) }
      when Array then node.each { |v| strings(v, acc) }
      when String then acc << node
      end
      acc
    end

    def blank?(v)
      v.nil? || v.to_s.strip.empty?
    end
  end
end
