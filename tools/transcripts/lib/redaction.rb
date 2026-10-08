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
      # Backblaze B2 application keys (legacy K00… form).
      %r{(?<![A-Za-z0-9+/])K00[0-9A-Za-z+/]{25,}(?![A-Za-z0-9+/=])},
      /\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/,
      %r{\bBearer\s+[A-Za-z0-9._~+/-]{20,}=*},
      # Authorization headers in any scheme (Basic, Token, Digest, …).
      %r{\bAuthorization["']?\s*[:=]\s*["']?(?:[A-Za-z-]+\s+)?[A-Za-z0-9._~+/=-]{8,}}i,
      # curl -u user:password
      %r{(?:(?<=\s)-u|--user)\s+["']?[^\s:"']+:[^\s"']+},
      # A value assigned to a name that ends in key, secret, token, password
      # or auth: ANTHROPIC_API_KEY=…, "applicationKey": "…", password: ….
      %r{(?<![A-Za-z0-9])[A-Za-z0-9_.-]*?(?:key|secret|token|passw(?:or)?d|passwd|pwd|auth|credentials?)["']?\s*(?:[:=]|=>)\s*["']?[A-Za-z0-9_\-./+=]{12,}}i,
      # Credentials in a URL: scheme://user:password@host
      %r{\b[a-z][a-z0-9+.-]*://[^\s/:@]+:[^\s/@]+@}i
    ].freeze

    # Home directories, mounts and temp paths on any of the fleet's systems.
    # A quoted path may contain spaces; take it to the closing quote.
    QUOTED_PATH_PATTERN = %r{(?<=['"`])(?:~|/Users|/home|/root|/mango|/var/folders|/private|/Volumes|/mnt|/media|/opt/homebrew)/[^'"`\n]*(?=['"`])}
    PATH_PATTERN = %r{(?<![\w.~/-])(?:~|/Users|/home|/root|/mango|/var/folders|/private|/Volumes|/mnt|/media|/opt/homebrew|[A-Z]:\\Users)[/\\][^\s'"`)\]>,;]*|(?:file|obsidian|vscode|cursor|codex|claude)://[^\s'"`)\]>]+}

    # Links an agent writes relative to the home directory (Desktop/…).
    HOME_RELATIVE_PATTERN = %r{(?<![\w.~/%-])(?:Desktop|Documents|Downloads|Library|Movies|Music|Pictures|Dropbox)/[^\s'"`)\]>,;]*}

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
    # A bare 40-character AWS secret access key, which may contain "/".
    AWS_SECRET_CANDIDATE = %r{(?<![A-Za-z0-9+/=])[A-Za-z0-9+/]{40}(?![A-Za-z0-9+/=])}

    # After a home path, a space followed by a word with a slash is still the
    # path ("/Users/x/Private Project/notes.md").
    PATH_CONTINUATION = %r{\A [^\s'"`)\]>,;]*[/\\][^\s'"`)\]>,;]*}

    # The only kinds a digest's redaction.allow list can clear: both have
    # ordinary-word false positives. Secrets, paths and addresses never.
    ALLOWABLE = %w[host email].freeze
    # When matches overlap they merge, and the merged span takes the most
    # serious kind.
    RANK = %w[secret path address host email].freeze

    module_function

    # Findings in one string. An allowed phrase clears only host and email
    # findings that fall wholly inside it.
    def scan(text, where: nil, allow: [])
      return [] unless text.is_a?(String) && !text.empty?

      allowed = allowed_ranges(text, allow)
      spans(text).filter_map do |range, kind|
        next if ALLOWABLE.include?(kind) && allowed.any? { |a| a.cover?(range.begin) && a.cover?(range.end - 1) }

        Finding.new(kind: kind, match: text[range], where: where)
      end
    end

    def redact(text)
      return text unless text.is_a?(String)

      spans(text).reverse.each_with_object(text.dup) { |(range, kind), out| out[range] = format(MARKER, kind) }
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

    # Every match in the text, overlapping ones merged, in order.
    def spans(text)
      found = []
      add = ->(kind, md) { found << [md.begin(0)...md.end(0), kind] }

      SECRET_PATTERNS.each { |re| text.to_enum(:scan, re).each { add.call("secret", Regexp.last_match) } }
      text.to_enum(:scan, QUOTED_PATH_PATTERN).each { add.call("path", Regexp.last_match) }
      [PATH_PATTERN, HOME_RELATIVE_PATTERN].each do |re|
        text.to_enum(:scan, re).each do
          md = Regexp.last_match
          stop = md.end(0)
          while (more = PATH_CONTINUATION.match(text[stop..]))
            stop += more[0].length
          end
          found << [md.begin(0)...stop, "path"]
        end
      end
      text.to_enum(:scan, TAILNET_PATTERN).each { add.call("host", Regexp.last_match) }
      text.to_enum(:scan, ADDRESS_PATTERN).each { add.call("address", Regexp.last_match) }
      text.to_enum(:scan, EMAIL_PATTERN).each do
        md = Regexp.last_match
        add.call("email", md) unless PUBLIC_EMAILS.include?(md[0].downcase)
      end
      text.to_enum(:scan, /[A-Za-z0-9][A-Za-z0-9-]*[A-Za-z0-9]|[A-Za-z0-9]/).each do
        md = Regexp.last_match
        add.call("host", md) if host?(md[0])
      end
      [ENTROPY_CANDIDATE, AWS_SECRET_CANDIDATE].each do |re|
        text.to_enum(:scan, re).each do
          md = Regexp.last_match
          add.call("secret", md) if key_like?(md[0])
        end
      end
      merge(found)
    end

    def merge(found)
      found.sort_by { |range, _| [range.begin, -range.end] }.each_with_object([]) do |(range, kind), out|
        last = out.last
        if last && range.begin < last[0].end
          stop = [last[0].end, range.end].max
          worse = [last[1], kind].min_by { |k| RANK.index(k) }
          out[-1] = [last[0].begin...stop, worse]
        else
          out << [range, kind]
        end
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

    def allowed_ranges(text, allow)
      Array(allow).flat_map do |phrase|
        next [] if phrase.to_s.empty?

        text.to_enum(:scan, phrase.to_s).map { (Regexp.last_match.begin(0)...Regexp.last_match.end(0)) }
      end
    end
  end
end
