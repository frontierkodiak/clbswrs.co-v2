# frozen_string_literal: true

require_relative "../session"

module Transcripts
  module Adapters
    # Codex rollouts: ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl. Each line
    # is {timestamp, type, payload}. What a person typed is logged three ways
    # across Codex versions: an event_msg "user_message", an item_completed
    # "UserMessage", and a response_item user message that also carries the
    # injected context (AGENTS.md, environment, permissions). The first two
    # are used when present; otherwise the third, with injected parts removed.
    module Codex
      TOOL_ITEMS = %w[
        function_call custom_tool_call local_shell_call web_search_call
        tool_search_call image_generation_call mcp_tool_call
      ].freeze
      INJECTED = /\A\s*(?:<[a-z_ -]+>|# AGENTS\.md instructions|<INSTRUCTIONS>)/i
      DISPATCHERS = /calyx|multica|exec|sdk|mcp|subagent/i

      module_function

      def read(path)
        events = []
        items = []
        fallback = []
        messages = []
        models = []
        times = []
        tool_calls = 0
        meta = {}
        tokens = nil
        reasoning = []

        Adapters.each_record(path) do |r|
          p = r["payload"] || r
          t = Adapters.time(r["timestamp"])
          times << t if t

          case r["type"]
          when "session_meta"
            meta = p
          when "turn_context"
            models << p["model"] if p["model"]
          when "event_msg"
            case p["type"]
            when "user_message"
              events << [t, p["message"].to_s]
            when "item_completed"
              it = p["item"] || {}
              if it["type"] == "UserMessage"
                items << [t, Array(it["content"]).map { |c| c["text"] }.compact.join("\n\n")]
              end
            when "thread_settings_applied"
              m = p.dig("thread_settings", "model")
              models << m if m
            when "token_count"
              tokens = p.dig("info", "total_token_usage") || tokens
            end
          when "compacted"
            next
          else
            case p["type"]
            when "message"
              if p["role"] == "user"
                text = Array(p["content"]).map { |c| c["text"] }.compact.reject { |s| s.match?(INJECTED) }.join("\n\n")
                fallback << [t, text] unless text.strip.empty?
              elsif p["role"] == "assistant"
                text = Array(p["content"]).map { |c| c["text"] }.compact.join("\n\n").strip
                next if text.empty?

                why = reasoning.join("\n\n").strip
                reasoning = []
                messages << Message.new(role: "a", at: t, text: text, reasoning: why.empty? ? nil : why)
              end
            when "reasoning"
              reasoning.concat(Array(p["summary"]).map { |s| s["text"] }.compact)
              reasoning.concat(Array(p["content"]).map { |s| s["text"] }.compact)
            when *TOOL_ITEMS
              tool_calls += 1
            end
          end
        end

        origin = dispatched?(meta) ? "dispatched" : "unknown"
        humans = [events, items, fallback].find { |list| !list.empty? } || []
        humans.each do |t, text|
          text = unwrap(text.strip)
          next if text.empty? || text.match?(INJECTED)

          messages << Message.new(role: "h", at: t, text: text, origin: origin)
        end
        start = Adapters.time(meta["timestamp"]) || times.min
        messages.each { |m| m.at ||= start }
        messages.sort_by!.with_index { |m, i| [m.at, m.role == "h" ? 0 : 1, i] }

        warnings = []
        warnings << "no human messages found" if humans.empty?
        warnings << "originator #{meta["originator"].inspect}: the human turns may be an orchestrator's brief" if origin == "dispatched"

        Session.new(
          harness: "codex", harness_version: meta["cli_version"], session: meta["id"] || meta["session_id"],
          models: models.uniq, started: messages.map(&:at).min || start, ended: messages.map(&:at).max || times.max,
          messages: messages, tool_calls: tool_calls, cost: nil,
          tokens: tokens && tokens.slice("input_tokens", "cached_input_tokens", "output_tokens", "reasoning_output_tokens"),
          warnings: warnings, **Adapters.file_facts(path)
        )
      end

      # Codex Desktop wraps a message that has attachments:
      #   # Files mentioned by the user:  ## <name>: <path> … ## My request for Codex:  <text>
      def unwrap(text)
        return text unless text.start_with?("# Files mentioned by the user:")

        files, request = text.split(/^## My request for Codex:\s*$/, 2)
        names = files.scan(/^## (.+?): /).flatten
        [*names.map { |n| "[attached: #{n}]" }, request.to_s.strip].reject(&:empty?).join("\n")
      end

      def dispatched?(meta)
        [meta["originator"], meta["source"]].compact.any? { |v| v.to_s.match?(DISPATCHERS) }
      end
    end
  end
end
