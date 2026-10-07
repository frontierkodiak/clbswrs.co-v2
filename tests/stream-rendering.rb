# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require "nokogiri"
require "time"

root = File.expand_path("..", __dir__)
literal = "  “A quotation.” 🦋\n---\n{{ site.secret }}\n<script>alert(\"no\")</script>\nLast line  "
ns = { "a" => "http://www.w3.org/2005/Atom" }

def check(condition, message)
  raise message unless condition
end

def validate_atom(path, ns)
  xml = Nokogiri::XML(File.read(path)) { |config| config.strict.nonet }
  check(xml.at_xpath("/a:feed/a:id", ns), "Missing feed id")
  check(xml.at_xpath("/a:feed/a:title", ns), "Missing feed title")
  check(xml.at_xpath("/a:feed/a:author/a:name", ns), "Missing feed author")
  Time.iso8601(xml.at_xpath("/a:feed/a:updated", ns).text)
  ids = xml.xpath("/a:feed/a:entry/a:id", ns).map(&:text)
  check(ids.uniq == ids, "Duplicate Atom ids")
  xml.xpath("/a:feed/a:entry", ns).each do |entry|
    %w[id title updated content].each do |field|
      check(entry.at_xpath("a:#{field}", ns), "Missing entry #{field}")
    end
    Time.iso8601(entry.at_xpath("a:updated", ns).text)
    Time.iso8601(entry.at_xpath("a:published", ns).text)
    check(entry.at_xpath("a:link", ns)["href"].start_with?("https://clbswrs.co/"), "Bad permalink")
  end
  xml
end

validate_atom(File.join(root, "_site/stream/atom.xml"), ns)
Dir.mktmpdir("clbswrs-stream-") do |temporary|
  source = File.join(temporary, "source")
  destination = File.join(temporary, "site")
  FileUtils.mkdir_p(source)
  Dir.children(root).reject { |name| name.start_with?(".") || %w[_site vendor].include?(name) }.each do |name|
    FileUtils.cp_r(File.join(root, name), source)
  end
  data = {
    kind: "quotation", date: "2026-10-07T14:53:00-04:00", title: "", text: literal,
    reaction: "Reaction & <tag>", source_title: "Source & <title>",
    source_url: "https://example.org/article?a=1&b=2", source_author: "Name",
    tags: ["ecology", "art"], date_source: "Synthetic test fixture; not published."
  }
  File.write(File.join(source, "_stream/fixture.md"), "---\n#{JSON.pretty_generate(data)}\n---\n")
  note = data.merge(kind: "note", text: "Untitled note", date: "2026-10-06T00:30:00-04:00",
                    updated: "2026-10-08T10:00:00-04:00", title: "")
  File.write(File.join(source, "_stream/note-fixture.md"), "---\n#{JSON.generate(note)}\n---\n")
  link = data.merge(kind: "link", text: "Link comment", date: "2026-10-05T23:30:00-04:00")
  File.write(File.join(source, "_stream/link-fixture.md"), "---\n#{JSON.generate(link)}\n---\n")
  check(system({ "JEKYLL_ENV" => "production" }, "bundle", "exec", "jekyll", "build", "--source", source,
               "--destination", destination, "--quiet"), "Fixture build failed")
  html = Nokogiri::HTML(File.read(File.join(destination, "stream/index.html")))
  check(html.at_css(".stream-text").text == literal, "Rendered text was changed")
  check(html.css(".stream-entry script").empty?, "Text became executable HTML")
  check(html.css(".stream-day").first.text.strip == "October 7, 2026", "Wrong day grouping")
  check(html.css(".stream-meta time").first.text == "2:53 pm", "Wrong local timestamp")
  check(html.at_css(".stream-credit a")["href"] == data[:source_url], "Changed source URL")
  check(html.css(".stream-entry")[1].css("h3").empty?, "Untitled note gained a title")
  check(html.css(".stream-entry")[2].text.include?("Link comment"), "Link missing")
  check(File.exist?(File.join(destination, "stream/fixture/index.html")), "Missing permalink")
  check(File.read(File.join(destination, "llms-full.txt")).include?(literal), "Plain text changed")
  atom = validate_atom(File.join(destination, "stream/atom.xml"), ns)
  check(atom.at_xpath("/a:feed/a:updated", ns).text == note[:updated], "An older entry's edit did not update the feed")
  body = Nokogiri::HTML.fragment(atom.at_xpath("/a:feed/a:entry/a:content", ns).text)
  check(body.at_css(".stream-text").text == literal, "Atom text changed")
end
puts "Atom structure, literal text, escaping, mixed kinds, dates and permalinks validated."
