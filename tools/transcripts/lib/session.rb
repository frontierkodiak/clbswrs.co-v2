# frozen_string_literal: true

require "digest"
require "json"
require "time"

module Transcripts
  # What an adapter reads out of one raw log. `messages` holds only what a
  # person or the agent said, in log order; tool calls are counted, not kept.
  Session = Struct.new(
    :harness, :harness_version, :session, :models, :started, :ended,
    :messages, :tool_calls, :cost, :tokens, :sha256, :bytes, :warnings,
    keyword_init: true
  )

  # role: "h" or "a". origin (human messages): "typed", "dispatched" (an
  # orchestrator wrote it) or "unknown".
  Message = Struct.new(:role, :at, :text, :reasoning, :origin, keyword_init: true)

  module Adapters
    module_function

    def each_record(path)
      File.foreach(path, encoding: "UTF-8") do |line|
        next if line.strip.empty?

        begin
          yield JSON.parse(line)
        rescue JSON::ParserError
          next
        end
      end
    end

    def file_facts(path)
      { sha256: ::Digest::SHA256.file(path).hexdigest, bytes: File.size(path) }
    end

    def time(value)
      case value
      when Numeric then Time.at(value).utc
      when String then Time.iso8601(value).utc
      end
    rescue ArgumentError
      nil
    end
  end
end
