# frozen_string_literal: true

require_relative "../tools/transcripts/lib/digest"

# Checks every transcript digest after the site is read and before anything is
# rendered. Any finding (a secret, a private path, a host name, a draft, a
# rule the turns don't keep) stops the build. Then it attaches the computed
# fields the includes print, under `_` in each digest, and indexes digests by
# the work item they belong to in `site.data.transcript_works`.
Jekyll::Hooks.register :site, :post_read do |site|
  digests = site.data["transcripts"] || {}
  drafts_allowed = ENV["TRANSCRIPT_DRAFTS"] == "1"

  errors = digests.flat_map do |id, data|
    Transcripts::Digest.validate(id, data, drafts_allowed: drafts_allowed)
  end
  pages = site.pages.select { |p| p.data["digest"] }
  pages.each do |p|
    errors << "#{p.path}: no digest named #{p.data["digest"].inspect}" unless digests.key?(p.data["digest"])
  end
  unless errors.empty?
    raise Jekyll::Errors::FatalException,
          "Transcript check failed; nothing was rendered.\n  " + errors.join("\n  ")
  end

  works = Hash.new { |h, k| h[k] = { "digests" => [] } }
  digests.sort_by { |_, d| d.dig("source", "started").to_s }.each do |id, data|
    page = pages.find { |p| p.data["digest"] == id }
    data["_"] = Transcripts::Digest.derive(id, data, url: page&.url)
    works[data.dig("work", "id")]["digests"] << id
  end
  works.each_value { |w| w["sessions"] = w["digests"].length }
  site.data["transcript_works"] = works.to_h
end
