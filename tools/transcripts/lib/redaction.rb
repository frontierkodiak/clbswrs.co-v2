# frozen_string_literal: true

require "digest"
require "set"

module Transcripts
  # Finds and replaces what must never reach a rendered page: secrets and
  # tokens, private filesystem paths, fleet host names, tailnet and private
  # network addresses, and email addresses. The site build runs `scan` over
  # every digest before rendering and fails on any finding; the adapters run
  # `redact` over a draft as they write it.
  module Redaction
    Finding = Struct.new(:kind, :match, :where, keyword_init: true) do
      # Enough to locate the finding without printing the secret itself.
      def preview
        s = match.to_s
        s.length <= 8 ? "#{s[0, 2]}…" : "#{s[0, 4]}…#{s[-2, 2]} (#{s.length} chars)"
      end
    end

    MARKER = "[redacted %s]"

    SECRET_PATTERNS = [
      /-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?(?:-----END [A-Z ]*PRIVATE KEY-----|\z)/,
      /\bsk-(?:ant-|proj-|svcacct-)?[A-Za-z0-9_-]{20,}/,
      /\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}/,
      /\bgithub_pat_[A-Za-z0-9_]{40,}/,
      /\bglpat-[A-Za-z0-9_-]{20,}/,
      /\bxox[abposr]-[A-Za-z0-9-]{10,}/,
      /\b(?:AKIA|ASIA)[0-9A-Z]{16}\b/,
      /\bAIza[0-9A-Za-z_-]{35}\b/,
      /\bhf_[A-Za-z0-9]{30,}/,
      /\blin_(?:api|oauth)_[A-Za-z0-9]{30,}/,
      /\br8_[A-Za-z0-9]{30,}/,
      /\bK00[0-9A-Za-z+\/]{28}\b/,
      /\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/,
      /\bBearer\s+[A-Za-z0-9._~+\/-]{20,}=*/,
      /(?:\b|(?<=_))(?:api[_-]?key|secret|token|passw(?:or)?d|pwd|auth)[A-Za-z0-9_]*["']?\s*[:=]\s*["']?[A-Za-z0-9_\-.\/+=]{12,}/i,
      %r{\b[a-z][a-z0-9+.-]*://[^\s/:@]+:[^\s/@]+@}i
    ].freeze

    # Home directories, mounts and temp paths on any of the fleet's systems.
    PATH_PATTERN = %r{(?<![\w.~/-])(?:~|/Users|/home|/root|/mango|/var/folders|/private|/Volumes|/mnt|/media|/opt/homebrew|[A-Z]:\\Users)[/\\][^\s'"`)\]>,;]*|(?:file|obsidian|vscode|cursor)://[^\s'"`)\]>]+}

    TAILNET_PATTERN = /\b[a-z0-9-]+(?:\.[a-z0-9-]+)*\.ts\.net\b|\btail[0-9a-f]{5}\b/i

    ADDRESS_PATTERN = /\b(?:100\.(?:6[4-9]|[7-9]\d|1[01]\d|12[0-7])|10\.\d{1,3}|192\.168|172\.(?:1[6-9]|2\d|3[01]))\.\d{1,3}\.\d{1,3}\b|\b(?:fd7a:115c:a1e0|fe80):[0-9a-f:]+/i

    EMAIL_PATTERN = /\b[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}\b/

    # Public on the site already (footer).
    PUBLIC_EMAILS = %w[caleb@polli.ai].freeze

    # Fleet host names, stored as SHA-256 prefixes so this public repository
    # doesn't carry an inventory of the machines. This is tidiness, not
    # secrecy: the names are ordinary words. The last entry is "examplehost",
    # used by the tests. Add one with
    #   printf '%s' NAME | shasum -a 256 | cut -c1-16
    HOST_HASHES = %w[
      13ffbb2f9bbad7fa 28d79d50ff515a79 b9af17af4fc5708e 90783486b4b0693c
      4a4dcff88700d627 5a50650c21065a26 0dd462cff114158d 71eba4d6bd8b370d
      e82f602281da4e69 72a6bb41849f9360 80cd70a6bbe912fa
      ef58ffb9725a9b51
    ].to_set.freeze

    # Long mixed-case alphanumeric runs that look like keys. Pure hex (git
    # and content hashes, UUIDs) is left alone.
    ENTROPY_CANDIDATE = /(?<![A-Za-z0-9+=_-])[A-Za-z0-9+_-]{32,}={0,2}(?![A-Za-z0-9+=_-])/

    module_function

    def scan(text, where: nil, allow: [])
      return [] unless text.is_a?(String) && !text.empty?

      text = mask_allowed(text, allow)
      findings = []
      each_match(text) { |kind, match| findings << Finding.new(kind: kind, match: match, where: where) }
      findings
    end

    def redact(text, allow: [])
      return text unless text.is_a?(String)

      spans = []
      each_match(mask_allowed(text, allow)) { |kind, _match, range| spans << [range, kind] }
      spans.sort_by { |range, _| -range.begin }.each_with_object(text.dup) do |(range, kind), out|
        out[range] = format(MARKER, kind)
      end
    end

    # Walks a parsed digest and scans every string in it, so nothing the
    # include could print escapes the check.
    def scan_tree(node, path = [], allow: [], &block)
      case node
      when Hash then node.each { |k, v| scan_tree(v, path + [k.to_s], allow: allow, &block) }
      when Array then node.each_with_index { |v, i| scan_tree(v, path + [i], allow: allow, &block) }
      when String then scan(node, where: path.join("."), allow: allow).each(&block)
      end
    end

    def each_match(text)
      taken = []
      emit = lambda do |kind, md|
        range = md.begin(0)...md.end(0)
        next if taken.any? { |t| t.cover?(range.begin) || range.cover?(t.begin) }

        taken << range
        yield kind, md[0], range
      end

      SECRET_PATTERNS.each { |re| text.to_enum(:scan, re).each { emit.call("secret", Regexp.last_match) } }
      text.to_enum(:scan, PATH_PATTERN).each { emit.call("path", Regexp.last_match) }
      text.to_enum(:scan, TAILNET_PATTERN).each { emit.call("host", Regexp.last_match) }
      text.to_enum(:scan, ADDRESS_PATTERN).each { emit.call("address", Regexp.last_match) }
      text.to_enum(:scan, EMAIL_PATTERN).each do
        md = Regexp.last_match
        emit.call("email", md) unless PUBLIC_EMAILS.include?(md[0].downcase)
      end
      text.to_enum(:scan, /[A-Za-z0-9][A-Za-z0-9-]*[A-Za-z0-9]|[A-Za-z0-9]/).each do
        md = Regexp.last_match
        emit.call("host", md) if host?(md[0])
      end
      text.to_enum(:scan, ENTROPY_CANDIDATE).each do
        md = Regexp.last_match
        emit.call("secret", md) if key_like?(md[0])
      end
    end

    def host?(word)
      ([word] + word.split("-")).uniq.any? do |w|
        HOST_HASHES.include?(::Digest::SHA256.hexdigest(w.downcase)[0, 16])
      end
    end

    def key_like?(s)
      return false if s.match?(/\A[0-9a-fA-F-]+\z/)
      return false unless s.match?(/[a-z]/) && s.match?(/[A-Z]/) && s.match?(/\d/)

      counts = s.each_char.tally
      entropy = counts.values.sum { |c| p = c.fdiv(s.length); -p * Math.log2(p) }
      entropy >= 4.0
    end

    # Allowed phrases are blanked out (same length, so positions hold) before
    # matching. Each digest's allow list is reviewed with the digest.
    def mask_allowed(text, allow)
      return text if allow.nil? || allow.empty?

      allow.reduce(text) { |t, phrase| t.gsub(phrase) { |m| " " * m.length } }
    end
  end
end
