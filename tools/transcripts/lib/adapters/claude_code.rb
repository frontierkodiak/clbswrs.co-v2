# frozen_string_literal: true

require_relative "../session"

module Transcripts
  module Adapters
    # Claude Code session logs: ~/.claude/projects/<project>/<session-id>.jsonl,
    # one JSON record per line. Subagent (sidechain) records are left out.
    module ClaudeCode
      INJECTED = [
        "<task-notification>", "<local-command-caveat>", "<local-command-stdout>",
        "<command-name>", "<command-message>", "<bash-input>", "<bash-stdout>",
        "<system-reminder>", "[Request interrupted", "Caveat: The messages below"
      ].freeze

      module_function

      def read(path)
        messages = []
        models = []
        tool_calls = 0
        times = []
        version = session = cost = pending = last_id = nil
        usage = Hash.new(0)
        counted = {}

        Adapters.each_record(path) do |r|
          t = Adapters.time(r["timestamp"])
          times << t if t
          session ||= r["sessionId"]
          version = r["version"] if r["version"]
          cost = r["totalCostUSD"] if r["type"] == "cost-state" && r["totalCostUSD"]
          next if r["isSidechain"]

          case r["type"]
          when "user"
            msg = human_message(r, t)
            messages << msg if msg
          when "assistant"
            m = r["message"] || {}
            models << m["model"] if m["model"] && !m["model"].start_with?("<")
            content = Array(m["content"])
            tool_calls += content.count { |b| b["type"] == "tool_use" }
            # One API message is logged as one record per content block, each
            # carrying the same usage; count it once.
            unless counted[m["id"]]
              counted[m["id"]] = true
              %w[input_tokens output_tokens cache_read_input_tokens cache_creation_input_tokens].each do |k|
                usage[k] += m.dig("usage", k).to_i
              end
            end
            text = content.select { |b| b["type"] == "text" }.map { |b| b["text"] }.join("\n\n").strip
            thinking = content.select { |b| b["type"] == "thinking" }.map { |b| b["thinking"] }.compact.join("\n\n").strip
            next if text.empty? && thinking.empty?

            # Reasoning arrives in its own record just before the text it led to.
            reasoning = [pending, thinking].compact.reject(&:empty?).join("\n\n")
            if text.empty?
              pending = reasoning
              next
            end
            pending = nil
            last = messages.last
            if last&.role == "a" && last_id && last_id == m["id"]
              last.text = "#{last.text}\n\n#{text}"
            else
              messages << Message.new(role: "a", at: t, text: text, reasoning: reasoning.empty? ? nil : reasoning)
            end
            last_id = m["id"]
          end
        end

        Session.new(
          harness: "claude-code", harness_version: version, session: session,
          models: models.uniq, started: times.min, ended: times.max,
          messages: messages, tool_calls: tool_calls,
          cost: cost && { "usd" => cost.round(2), "basis" => "at API prices, as reported by Claude Code" },
          tokens: usage.empty? ? nil : usage.to_h, warnings: [], **Adapters.file_facts(path)
        )
      end

      def human_message(r, t)
        return if r["isMeta"] || r["isCompactSummary"] || r["toolUseResult"]
        return if r["promptSource"] == "system" || r["turnOrigin"] == "task_notification"

        content = r.dig("message", "content")
        text = case content
               when String then content
               when Array
                 return if content.any? { |b| b["type"] == "tool_result" }

                 content.select { |b| b["type"] == "text" }.map { |b| b["text"] }.join("\n\n")
               end.to_s
        text = text.gsub(%r{<system-reminder>.*?</system-reminder>}m, "").strip
        return if text.empty? || INJECTED.any? { |p| text.start_with?(p) }

        origin = case r["promptSource"]
                 when "typed", "queued" then "typed"
                 when "sdk" then r["turnOrigin"] == "human" ? "typed" : "dispatched"
                 else r["entrypoint"] == "sdk-cli" ? "dispatched" : "unknown"
                 end
        Message.new(role: "h", at: t, text: text, origin: origin)
      end
    end
  end
end
