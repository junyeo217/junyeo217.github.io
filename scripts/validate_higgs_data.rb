require "digest"
require "fileutils"
require "json"
require "nokogiri"
require "optparse"
require "time"
require_relative "higgs_html_safety"

repo_root = File.expand_path("..", __dir__)
options = { report: nil }
OptionParser.new do |parser|
  parser.on("--report PATH") { |path| options[:report] = File.expand_path(path, repo_root) }
end.parse!(ARGV)

target = ARGV.shift || File.join(repo_root, "higgs-data", "index.html")
errors = []

def normalized_text_length(node)
  node.text.gsub(/\s+/, " ").strip.length
end

def explanatory_text_length(node)
  copy = Nokogiri::HTML5.fragment(node.inner_html)
  copy.css("pre, code").remove
  normalized_text_length(copy)
end

CASE_METADATA_FIELDS = %w[
  character_count tool resolution dimensions aspect generation_count output_count
].freeze

def case_metadata_display(field, value)
  labels = {
    "character_count" => "chars",
    "tool" => "tool",
    "resolution" => "resolution",
    "dimensions" => "dimensions",
    "aspect" => "aspect",
    "generation_count" => "generations",
    "output_count" => "outputs"
  }
  "#{labels.fetch(field)}: #{value}"
end

unless File.file?(target)
  warn "HIGGS_DATA_INVALID missing_file=#{target}"
  exit 1
end

html = File.read(target, encoding: "UTF-8")
document = Nokogiri::HTML5.parse(html)
tabs = document.css('[role="tab"]')
panels = document.css('[role="tabpanel"]')
ids = document.css("[id]").map { |node| node["id"] }
id_set = ids.to_h { |id| [id, true] }

errors.concat(HiggsHtmlSafety.final_document_errors(document))
document.css("img[src]").each do |image|
  errors << "non-local public image" unless image["src"].to_s.start_with?("/higgs-data/media/")
end

errors << "expected 8 tabs, got #{tabs.length}" unless tabs.length == 8
errors << "expected 8 panels, got #{panels.length}" unless panels.length == 8
errors << "duplicate ids: #{ids.tally.select { |_id, count| count > 1 }.keys.join(', ')}" unless ids.uniq.length == ids.length
selected_tabs = tabs.select { |tab| tab["aria-selected"] == "true" }
visible_panels = panels.select { |panel| panel["hidden"].nil? }
errors << "expected one selected tab" unless selected_tabs.length == 1
errors << "expected one initially visible panel" unless visible_panels.length == 1

if selected_tabs.length == 1 && visible_panels.length == 1
  controlled_panel = selected_tabs.first["aria-controls"]
  visible_panel = visible_panels.first["id"]
  errors << "selected tab controls #{controlled_panel}, but visible panel is #{visible_panel}" unless controlled_panel == visible_panel
end

expected_values = %w[overview adiliada cully-hill-boys hell-grind kok-bory oneiric zephyr-special author]
actual_values = tabs.map { |tab| tab["data-tab-value"] }
errors << "tab values mismatch: #{actual_values.inspect}" unless actual_values == expected_values

tabs.each do |tab|
  panel_id = tab["aria-controls"]
  panel = panel_id && document.at_css("##{panel_id}")
  errors << "tab #{tab['id']} has missing panel #{panel_id}" unless panel
  errors << "tab #{tab['id']} does not control a tabpanel" if panel && panel["role"] != "tabpanel"
end

panels.each do |panel|
  label_id = panel["aria-labelledby"]
  label = label_id && document.at_css("##{label_id}")
  errors << "panel #{panel['id']} has missing label #{label_id}" unless label
  errors << "panel #{panel['id']} must contain exactly one h1" unless panel.css("h1").length == 1
end

content_panel_ids = %w[
  panel-overview panel-adiliada panel-cully panel-hell
  panel-kok panel-oneiric panel-zephyr
]
project_panel_ids = content_panel_ids.drop(1)
content_audit = {}

content_panel_ids.each do |panel_id|
  panel = document.at_css("##{panel_id}")
  next unless panel

  content_audit[panel_id] = {
    text_chars: normalized_text_length(panel),
    explanatory_text_chars: explanatory_text_length(panel),
    section_navs: panel.css("[data-section-nav]").length,
    charts: panel.css("[data-chart]").length,
    prompt_quotes: panel.css("[data-prompt-quote]").length,
    techniques: panel.css("[data-technique]").length,
    cases: panel.css("[data-case]").length,
    derived_insights: panel.css("[data-derived-insight]").length,
    zero_findings: panel.css("[data-zero-finding]").length,
    evidence_claims: panel.css("[data-claim][data-evidence-grade]").length
  }

  errors << "#{panel_id} text_chars must be at least 8000" if content_audit[panel_id][:text_chars] < 8_000
  if content_audit[panel_id][:explanatory_text_chars] < 8_000
    errors << "#{panel_id} explanatory_text_chars excluding pre/code must be at least 8000"
  end
  errors << "#{panel_id} must contain exactly one section navigator" unless content_audit[panel_id][:section_navs] == 1
end

overview_audit = content_audit["panel-overview"]
if overview_audit
  errors << "overview must contain at least 3 charts" if overview_audit[:charts] < 3
  errors << "overview must contain a technique matrix" unless document.at_css("#panel-overview [data-technique-matrix]")
  errors << "overview must contain contradictory practices" unless document.at_css("#panel-overview [data-conflict-set]")
  errors << "overview must contain a correction record" unless document.at_css("#panel-overview [data-correction-record]")
end

project_panel_ids.each do |panel_id|
  audit = content_audit[panel_id]
  next unless audit

  errors << "#{panel_id} must contain at least 2 charts" if audit[:charts] < 2
  errors << "#{panel_id} must contain at least 6 prompt quotes" if audit[:prompt_quotes] < 6
  errors << "#{panel_id} techniques must be 4..6" unless (4..6).cover?(audit[:techniques])
  errors << "#{panel_id} cases must be 2..3" unless (2..3).cover?(audit[:cases])
  errors << "#{panel_id} must contain a derived insight" if audit[:derived_insights] < 1
  errors << "#{panel_id} must contain a measured zero finding or D-grade corpus limitation" if audit[:zero_findings] < 1

  document.css("##{panel_id} [data-prompt-quote]").each_with_index do |quote, index|
    errors << "#{panel_id} quote #{index + 1} must contain details" unless quote.at_css("details")
    errors << "#{panel_id} quote #{index + 1} must contain pre > code" unless quote.at_css("pre > code")
    errors << "#{panel_id} quote #{index + 1} missing source key" if quote["data-source-key"].to_s.empty?
    errors << "#{panel_id} quote #{index + 1} missing explanation" unless quote.at_css("[data-quote-explanation]")
  end

  document.css("##{panel_id} [data-case]").each_with_index do |item, index|
    media_states = item.css("[data-media-verified], [data-media-unavailable]")
    errors << "#{panel_id} case #{index + 1} must have exactly one media state" unless media_states.length == 1

    metadata = item.at_css("[data-case-metadata]")
    errors << "#{panel_id} case #{index + 1} missing metadata chips" unless metadata
    if metadata
      metadata_items = metadata.element_children
      fields = metadata_items.map { |child| child["data-case-meta-field"].to_s }
      errors << "#{panel_id} case #{index + 1} metadata fields mismatch" unless fields == CASE_METADATA_FIELDS
      metadata_items.each_with_index do |child, metadata_index|
        field = child["data-case-meta-field"].to_s
        value = child["data-case-source-value"].to_s
        errors << "#{panel_id} case #{index + 1} metadata #{metadata_index + 1} missing source key" if child["data-source-key"].to_s.empty?
        errors << "#{panel_id} case #{index + 1} metadata #{metadata_index + 1} missing source value" if value.empty?
        if CASE_METADATA_FIELDS.include?(field)
          expected_text = case_metadata_display(field, value)
          errors << "#{panel_id} case #{index + 1} metadata #{metadata_index + 1} display mismatch" unless child.text.strip == expected_text
        end
      end
    end

    excerpt = item.at_css("pre > code[data-case-prompt-excerpt]")
    errors << "#{panel_id} case #{index + 1} missing prompt excerpt" unless excerpt
    if excerpt
      errors << "#{panel_id} case #{index + 1} prompt excerpt is too short" if excerpt.text.strip.length < 20
      errors << "#{panel_id} case #{index + 1} prompt excerpt missing source key" if excerpt["data-source-key"].to_s.empty?
      errors << "#{panel_id} case #{index + 1} prompt excerpt missing SHA" if excerpt["data-excerpt-sha256"].to_s.empty?
      if metadata
        errors << "#{panel_id} case #{index + 1} metadata source mismatch" unless metadata["data-source-key"] == excerpt["data-source-key"]
        metadata.element_children.each do |child|
          errors << "#{panel_id} case #{index + 1} metadata item source mismatch" unless child["data-source-key"] == excerpt["data-source-key"]
        end
      end
    end

    points = item.css("[data-case-point]")
    errors << "#{panel_id} case #{index + 1} needs at least two quoted structure points" if points.length < 2
    points.each_with_index do |point, point_index|
      errors << "#{panel_id} case #{index + 1} point #{point_index + 1} missing exact quote" unless point.at_css("q[data-case-point-quote]")
      errors << "#{panel_id} case #{index + 1} point #{point_index + 1} missing explanation" unless point.at_css("[data-case-point-explanation]")
      errors << "#{panel_id} case #{index + 1} point #{point_index + 1} missing source key" if point["data-source-key"].to_s.empty?
    end

    if metadata && media_states.length == 1 && excerpt && points.any?
      descendants = item.xpath(".//*").to_a
      order = [metadata, media_states.first, excerpt, points.first].map { |node| descendants.index(node) }
      errors << "#{panel_id} case #{index + 1} anatomy must be metadata, media, prompt, points" unless order == order.sort
    end
  end
end

errors << "expected 12 case prompt excerpts" unless document.css("code[data-case-prompt-excerpt]").length == 12

valid_grades = %w[A B C D]
document.css("[data-claim]").each_with_index do |claim, index|
  grade = claim["data-evidence-grade"]
  errors << "claim #{index + 1} has invalid evidence grade #{grade.inspect}" unless valid_grades.include?(grade)
end

document.css("[data-chart], [data-prompt-quote], [data-derived-insight], [data-zero-finding]").each_with_index do |node, index|
  errors << "evidence-bearing node #{index + 1} missing source key" if node["data-source-key"].to_s.empty?
end

document.css("video").each_with_index do |video, index|
  %w[muted loop playsinline].each do |attribute|
    errors << "video #{index + 1} missing #{attribute}" unless video.key?(attribute)
  end
  errors << "video #{index + 1} preload must be none" unless video["preload"] == "none"
  errors << "video #{index + 1} missing poster" if video["poster"].to_s.empty?
end

document.css("[aria-labelledby]").each do |node|
  node["aria-labelledby"].to_s.split.each do |label_id|
    errors << "#{node.name} references missing label #{label_id}" unless id_set[label_id]
  end
end

text = document.text.gsub(/\s+/, " ")
projects = ["ADILIADA", "THE CULLY HILL BOYS", "HELL GRIND", "KOK_BORY", "ONEIRIC", "ZEPHYR Special"]
projects.each { |project| errors << "missing project #{project}" unless text.include?(project) }

["관찰된 사실", "팀 보고", "교차 해석", "검증 한계"].each do |label|
  errors << "missing evidence label #{label}" unless text.include?(label)
end

["188,850", "644,305", "430M", "292"].each do |value|
  errors << "missing corpus value #{value}" unless text.include?(value)
end

expected_contacts = {
  "Instagram" => "https://www.instagram.com/junyeo.ai/",
  "Threads" => "https://www.threads.net/@junyeo.ai",
  "Email" => "mailto:junyeo.ai@gmail.com",
  "Portfolio" => "https://junyeo217.github.io/"
}

expected_contacts.each do |label, href|
  link = document.at_css("a[href='#{href}']")
  errors << "missing #{label} contact #{href}" unless link
end

canonical = document.at_css('link[rel="canonical"]')
errors << "canonical mismatch" unless canonical && canonical["href"] == "https://junyeo217.github.io/higgs-data/"
errors << "missing Korean lang" unless document.at_css("html")["lang"] == "ko"
errors << "missing title" if document.at_css("title").to_s.strip.empty?
errors << "missing meta description" unless document.at_css('meta[name="description"][content]')

structured = document.at_css('script[type="application/ld+json"]')
begin
  parsed = JSON.parse(structured&.text.to_s)
  errors << "JSON-LD type mismatch" unless parsed["@type"] == "CollectionPage"
rescue JSON::ParserError => error
  errors << "invalid JSON-LD: #{error.message}"
end

document.css('link[href^="/"], script[src^="/"]').each do |node|
  value = node["href"] || node["src"]
  path = value.split("?", 2).first
  local = File.join(repo_root, path.delete_prefix("/"))
  errors << "missing local asset #{path}" unless File.file?(local)
end

forbidden = ["TODO", "FIXME", "lorem ipsum", "Jack Black", "copyright check", "levitatingant1150", "pocket_corallo_2"]
forbidden.each { |term| errors << "forbidden public term #{term}" if html.include?(term) }

sitemap = File.read(File.join(repo_root, "sitemap.xml"), encoding: "UTF-8")
route = "https://junyeo217.github.io/higgs-data/"
errors << "sitemap route count must be 1" unless sitemap.scan(route).length == 1

baseline_hashes = {
  "index.html" => "f32ab6d0063392568da5a7ed7d9b6b8a259e17810055b1aa515f891e2b79db49",
  "css/home.css" => "7830617bdcfd555a7619ff3136015d8c3b52c18df4f2b0b6092c477affeeaf38",
  "js/home.js" => "bea53a84eb3ca15a41f18dace437ccfc075b99ad4e1605d2de36087e4cd8698f",
  "css/main.css" => "658e1e2bdee46b8e8a644fda1dd71b1fdb888b16940d91eeaaf1d4fe3c539634",
  "js/main.js" => "2ad77be942ecca34e944c707939913e93312e294679b5c878eab3bf23526d17b"
}

baseline_hashes.each do |path, expected|
  actual = Digest::SHA256.file(File.join(repo_root, path)).hexdigest
  errors << "baseline changed #{path}: #{actual}" unless actual == expected
end

if options[:report]
  report = {
    schema_version: 1,
    generated_at: Time.now.utc.iso8601,
    target: target,
    document: {
      text_chars: normalized_text_length(document.at_css("body")),
      tables: document.css("table").length,
      svgs: document.css("svg").length,
      canvases: document.css("canvas").length,
      pre: document.css("pre").length,
      code: document.css("code").length,
      images: document.css("img").length,
      videos: document.css("video").length,
      details: document.css("details").length
    },
    panels: content_audit,
    errors: errors
  }
  FileUtils.mkdir_p(File.dirname(options[:report]))
  File.write(options[:report], JSON.pretty_generate(report) + "\n")
end

if errors.any?
  warn "HIGGS_DATA_INVALID count=#{errors.length}"
  errors.each { |error| warn "- #{error}" }
  exit 1
end

puts "HIGGS_DATA_VALID panels=8 projects=6 evidence_labels=4 contacts=4 unique_ids=#{ids.length} deep_panels=#{content_audit.length}"
