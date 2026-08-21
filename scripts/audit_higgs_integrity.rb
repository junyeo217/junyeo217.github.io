require "digest"
require "fileutils"
require "json"
require "nokogiri"
require "optparse"
require "pathname"
require "time"

PROJECT_KEYS = %w[
  ADILIADA Cully_Hill_Boys Hell_Grind KOK_BORY ONEIRIC ZEPHYR_Special
].freeze

CASE_METADATA_FIELDS = %w[
  character_count tool resolution dimensions aspect generation_count output_count
].freeze

def case_metadata_value(record, field)
  return "#{record.fetch('width')}x#{record.fetch('height')}" if field == "dimensions"

  record.fetch(field).to_s
end

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

def missing_evidence_texts(path, keyed_texts)
  pending = keyed_texts.to_h { |key, text| [key, text.to_s.b] }
  return pending.keys if pending.values.any?(&:empty?)

  maximum = pending.values.map(&:bytesize).max.to_i
  carry = "".b
  File.open(path, "rb") do |file|
    while (chunk = file.read(1_048_576))
      buffer = carry + chunk
      pending.delete_if { |_key, text| buffer.include?(text) }
      break if pending.empty?

      carry_bytes = [maximum - 1, buffer.bytesize].min
      carry = carry_bytes.positive? ? buffer.byteslice(buffer.bytesize - carry_bytes, carry_bytes) : "".b
    end
  end
  pending.keys
end

def source_manifest_files(source_root)
  files = []
  PROJECT_KEYS.each do |project_key|
    project_root = File.join(source_root, project_key)
    next unless Dir.exist?(project_root)

    prompts = Dir.glob(File.join(project_root, "**", "{prompts.md,prompts_part_*.md}"), File::FNM_EXTGLOB)
      .select { |path| path.include?("#{File::SEPARATOR}owners#{File::SEPARATOR}") }
    prompts.each { |path| files << [path, "prompt_archive"] }
    Dir.glob(File.join(project_root, "ULW_Research_Log", "*record-summary.json"))
      .each { |path| files << [path, "record_summary"] }
  end
  inventory = File.join(source_root, "Cully_Hill_Boys", "Cully_Hill_Boys_FOLDER_INVENTORY.md")
  files << [inventory, "folder_inventory"] if File.file?(inventory)
  files.sort_by(&:first)
end

def manifest_entry_id(path)
  Digest::SHA256.hexdigest(path)[0, 12]
end

def path_within?(path, root)
  path == root || path.start_with?(root + File::SEPARATOR)
end

repo_root = File.expand_path("..", __dir__)
options = {
  site: File.join(repo_root, "higgs-data"),
  source: nil,
  analysis: nil,
  report: nil
}

OptionParser.new do |parser|
  parser.on("--site PATH") { |path| options[:site] = File.expand_path(path, repo_root) }
  parser.on("--source PATH") { |path| options[:source] = File.expand_path(path) }
  parser.on("--analysis PATH") { |path| options[:analysis] = File.expand_path(path, repo_root) }
  parser.on("--report PATH") { |path| options[:report] = File.expand_path(path, repo_root) }
end.parse!(ARGV)

options[:analysis] ||= File.join(options[:site], "_data", "analysis.json")
errors = []
checks = []

unless options[:source] && Dir.exist?(options[:source])
  errors << "source directory is required"
end

html_path = File.join(options[:site], "index.html")
unless File.file?(html_path)
  warn "HIGGS_INTEGRITY_INVALID missing_html=#{html_path}"
  exit 1
end

public_paths = Dir.glob(File.join(options[:site], "**", "*.{html,css,js,json,xml}"))
  .reject { |path| path.include?("/_data/") }
public_text = public_paths.map { |path| File.read(path, encoding: "UTF-8") }.join("\n")

raw_user_ids = public_text.scan(/\buser_[A-Za-z0-9_-]+\b/).uniq
errors << "raw account ids exposed: #{raw_user_ids.join(', ')}" unless raw_user_ids.empty?

owner_handles = if options[:source] && Dir.exist?(options[:source])
  Dir.glob(File.join(options[:source], "**", "owners", "*"))
    .select { |path| File.directory?(path) }
    .map { |path| File.basename(path) }
    .uniq
else
  []
end
exposed_handles = owner_handles.select { |handle| public_text.include?(handle) }
errors << "owner handles exposed: #{exposed_handles.join(', ')}" unless exposed_handles.empty?

document = Nokogiri::HTML5.parse(File.read(html_path, encoding: "UTF-8"))
errors << "unsafe executable/embed elements present" unless document.css("iframe, object, embed, foreignObject, foreignobject, form, base").empty?
document.css("*").each do |node|
  node.attribute_nodes.each do |attribute|
    name = attribute.name.downcase
    value = attribute.value.to_s.strip
    errors << "inline event attribute #{name} on #{node.name}" if name.start_with?("on")
    errors << "srcdoc attribute on #{node.name}" if name == "srcdoc"
    if %w[href src srcset formaction action].include?(name) && value.match?(/\A(?:javascript|vbscript|data:text\/html)/i)
      errors << "executable URL on #{node.name}"
    end
    if name == "style" && value.match?(/(?:expression\s*\(|javascript\s*:|url\s*\()/i)
      errors << "unsafe inline style on #{node.name}"
    end
  end
end
document.css("script").each do |script|
  safe_json = script["type"] == "application/ld+json" && script["src"].nil?
  safe_local = script["src"].to_s.start_with?("/higgs-data/higgs-data.js?") && script.text.strip.empty?
  errors << "unsafe script element" unless safe_json || safe_local
end
document.css('link[rel~="stylesheet"]').each do |link|
  errors << "non-local stylesheet" unless link["href"].to_s.start_with?("/higgs-data/")
end
document.css("img[src]").each do |image|
  errors << "non-local public image" unless image["src"].to_s.start_with?("/higgs-data/media/")
end
quotes = document.css("[data-prompt-quote]")
errors << "expected at least 36 prompt quotes, got #{quotes.length}" if quotes.length < 36
errors << "public HTML references private _data" if document.to_html.include?("/higgs-data/_data/")

media_manifest_path = File.join(options[:site], "media", "SOURCES.json")
media_items = []
if File.file?(media_manifest_path)
  media_items = JSON.parse(File.read(media_manifest_path, encoding: "UTF-8")).fetch("items", [])
else
  errors << "missing media source manifest"
end

media_items.each do |item|
  media_path = File.join(options[:site], "media", item.fetch("file"))
  if File.file?(media_path)
    actual_sha = Digest::SHA256.file(media_path).hexdigest
    errors << "media sha mismatch #{item.fetch('file')}" unless actual_sha == item.fetch("sha256")
  else
    errors << "missing media file #{item.fetch('file')}"
  end
end

verified_media = document.css("[data-media-verified]")
unavailable_media = document.css("[data-media-unavailable]")
errors << "expected six verified poster states, got #{verified_media.length}" unless verified_media.length == 6
errors << "expected six unavailable video states, got #{unavailable_media.length}" unless unavailable_media.length == 6

verified_media.each_with_index do |state, index|
  image = state.at_css("img")
  if image
    filename = File.basename(image["src"].to_s)
    item = media_items.find { |candidate| candidate["file"] == filename }
    errors << "verified media #{index + 1} missing manifest item" unless item
    errors << "verified media #{index + 1} must use local Higgs media" unless image["src"] == "/higgs-data/media/#{filename}"
    errors << "verified media #{index + 1} missing alt" if image["alt"].to_s.strip.empty?
    errors << "verified media #{index + 1} must lazy load" unless image["loading"] == "lazy"
    errors << "verified media #{index + 1} must decode async" unless image["decoding"] == "async"
    if item
      errors << "verified media #{index + 1} width mismatch" unless image["width"].to_i == item["width"]
      errors << "verified media #{index + 1} height mismatch" unless image["height"].to_i == item["height"]
      errors << "verified media #{index + 1} missing official project link" unless state.at_css("a[href='#{item.fetch('project_page')}']")
    end
  else
    errors << "verified media #{index + 1} missing image"
  end
end

unavailable_media.each_with_index do |state, index|
  errors << "unavailable media #{index + 1} contains an empty player or image" if state.at_css("video, img")
end

analysis = nil
if File.file?(options[:analysis])
  analysis = JSON.parse(File.read(options[:analysis], encoding: "UTF-8"))
else
  errors << "missing analysis #{options[:analysis]}"
end

source_manifest = { count: 0, sha256: nil }
source_manifest_paths = []
if analysis.is_a?(Hash) && options[:source] && Dir.exist?(options[:source])
  source_root = File.realpath(options[:source])
  analysis_projects = analysis.fetch("projects", {}).keys.sort
  errors << "analysis project set mismatch" unless analysis_projects == PROJECT_KEYS.sort

  stored_entries = analysis.fetch("projects", {}).values.flat_map do |project|
    project.dig("private", "source_files").to_a
  end
  stored_paths = stored_entries.map { |entry| entry["path"].to_s }
  errors << "analysis source manifest has duplicate paths" unless stored_paths.uniq.length == stored_paths.length

  actual_entries = source_manifest_files(source_root).map do |path, kind|
    relative = Pathname.new(path).relative_path_from(Pathname.new(source_root)).to_s
    {
      "path" => relative,
      "sha256" => Digest::SHA256.file(path).hexdigest,
      "bytes" => File.size(path),
      "kind" => kind
    }
  end
  actual_paths = actual_entries.map { |entry| entry.fetch("path") }
  source_manifest_paths = actual_paths
  errors << "analysis source manifest file set mismatch" unless stored_paths.sort == actual_paths.sort

  stored_by_path = stored_entries.to_h { |entry| [entry["path"].to_s, entry] }
  actual_entries.each do |entry|
    stored = stored_by_path[entry.fetch("path")]
    next unless stored

    %w[sha256 bytes kind].each do |field|
      unless stored[field] == entry[field]
        errors << "source manifest entry #{manifest_entry_id(entry.fetch('path'))} #{field} mismatch"
      end
    end
  end

  manifest_payload = actual_entries.sort_by { |entry| entry.fetch("path") }.map do |entry|
    [entry.fetch("path"), entry.fetch("sha256"), entry.fetch("bytes"), entry.fetch("kind")].join("\0")
  end.join("\n")
  actual_manifest_sha = Digest::SHA256.hexdigest(manifest_payload)
  errors << "analysis source manifest sha mismatch" unless analysis["source_manifest_sha256"] == actual_manifest_sha
  source_manifest = { count: actual_entries.length, sha256: actual_manifest_sha }
end

evidence = analysis.is_a?(Hash) ? analysis.fetch("evidence", {}) : {}
verified_quotes = []
verified_case_excerpts = []

def resolve_analysis_path(analysis, path)
  path.to_s.split(".").reduce(analysis) do |value, segment|
    break nil unless value.is_a?(Hash) && value.key?(segment)
    value[segment]
  end
end

referenced_evidence_keys = (
  quotes.map { |node| node["data-source-key"].to_s } +
  document.css("code[data-case-prompt-excerpt]").map { |node| node["data-source-key"].to_s } +
  document.css("[data-case-point]").map { |node| node["data-source-key"].to_s } +
  document.css("[data-case-meta-field]").map { |node| node["data-source-key"].to_s }
).reject(&:empty?).uniq

source_membership_verified = {}
if options[:source] && Dir.exist?(options[:source])
  resolved_source_root = File.realpath(options[:source])
  grouped_records = referenced_evidence_keys.map do |key|
    record = evidence[key]
    [key, record] if record.is_a?(Hash)
  end.compact.group_by { |_key, record| record["source_relative_path"].to_s }

  grouped_records.each do |relative_path, pairs|
    if relative_path.empty? || !source_manifest_paths.include?(relative_path)
      pairs.each { |key, _record| errors << "evidence #{key} source path is outside the verified manifest" }
      next
    end

    candidate_path = File.expand_path(relative_path, resolved_source_root)
    unless File.file?(candidate_path)
      pairs.each { |key, _record| errors << "evidence #{key} source file is missing" }
      next
    end
    resolved_candidate = File.realpath(candidate_path)
    unless path_within?(resolved_candidate, resolved_source_root)
      pairs.each { |key, _record| errors << "evidence #{key} source path escapes the source root" }
      next
    end

    source_sha = Digest::SHA256.file(resolved_candidate).hexdigest
    sha_valid = {}
    pairs.each do |key, record|
      sha_valid[key] = source_sha == record["source_file_sha256"]
      errors << "evidence #{key} source file sha mismatch" unless sha_valid[key]
    end
    missing_keys = missing_evidence_texts(
      resolved_candidate,
      pairs.map { |key, record| [key, record.fetch("text", "")] }
    )
    missing_keys.each { |key| errors << "evidence #{key} prompt text is absent from raw source" }
    pairs.each do |key, _record|
      source_membership_verified[key] = true if sha_valid[key] && !missing_keys.include?(key)
    end
  end
end

numeric_leaf_nodes = document.css("[data-source-value]")
%w[panel-overview panel-adiliada panel-cully panel-hell panel-kok panel-oneiric panel-zephyr].each do |panel_id|
  count = document.css("##{panel_id} [data-source-value]").length
  errors << "#{panel_id} needs at least six machine-checked numeric leaves, got #{count}" if count < 6
end

numeric_leaf_nodes.each_with_index do |node, index|
  key = node["data-source-key"].to_s
  record = evidence[key]
  expected = if record.is_a?(Hash) && record["character_count"].is_a?(Numeric)
    record["character_count"]
  else
    resolve_analysis_path(analysis, key)
  end
  errors << "numeric leaf #{index + 1} missing scalar source #{key.inspect}" unless expected.is_a?(Numeric)
  errors << "numeric leaf #{index + 1} value mismatch #{key.inspect}" if expected.is_a?(Numeric) && node["data-source-value"] != expected.to_s
end

quotes.each_with_index do |quote, index|
  key = quote["data-source-key"].to_s
  record = evidence[key]
  if key.empty? || !record.is_a?(Hash)
    errors << "quote #{index + 1} has no analysis evidence for #{key.inspect}"
    next
  end

  text = quote.at_css("pre > code")&.text.to_s
  expected_text = record["text"].to_s
  errors << "quote #{key} text mismatch" unless text == expected_text

  prompt_sha = Digest::SHA256.hexdigest(expected_text)
  errors << "quote #{key} prompt sha mismatch" unless prompt_sha == record["prompt_sha256"]

  errors << "quote #{key} is not verified in raw source" unless source_membership_verified[key]

  if source_membership_verified[key]
    verified_quotes << {
      key: key,
      prompt_sha256: prompt_sha,
      source_file_sha256: record["source_file_sha256"],
      source_path: record["source_relative_path"]
    }
  end
end

verified_case_metadata = 0
case_metadata_containers = document.css("[data-case-metadata]")
errors << "expected 12 case metadata containers, got #{case_metadata_containers.length}" unless case_metadata_containers.length == 12
case_metadata_containers.each_with_index do |container, index|
  key = container["data-source-key"].to_s
  record = evidence[key]
  items = container.element_children
  fields = items.map { |item| item["data-case-meta-field"].to_s }
  errors << "case metadata #{index + 1} fields mismatch" unless fields == CASE_METADATA_FIELDS
  if !record.is_a?(Hash)
    errors << "case metadata #{index + 1} has no analysis evidence"
    next
  end
  errors << "case metadata #{index + 1} is not verified in raw source" unless source_membership_verified[key]

  items.each_with_index do |item, item_index|
    field = item["data-case-meta-field"].to_s
    next unless CASE_METADATA_FIELDS.include?(field)

    expected_value = case_metadata_value(record, field)
    declared_value = item["data-case-source-value"].to_s
    expected_display = case_metadata_display(field, expected_value)
    errors << "case metadata #{index + 1}.#{item_index + 1} source key mismatch" unless item["data-source-key"] == key
    errors << "case metadata #{index + 1}.#{item_index + 1} value mismatch" unless declared_value == expected_value
    errors << "case metadata #{index + 1}.#{item_index + 1} display mismatch" unless item.text.strip == expected_display
    if source_membership_verified[key] && declared_value == expected_value && item.text.strip == expected_display
      verified_case_metadata += 1
    end
  end
end

case_excerpts = document.css("code[data-case-prompt-excerpt]")
errors << "expected 12 case prompt excerpts, got #{case_excerpts.length}" unless case_excerpts.length == 12
case_excerpts.each_with_index do |code, index|
  key = code["data-source-key"].to_s
  record = evidence[key]
  if key.empty? || !record.is_a?(Hash)
    errors << "case excerpt #{index + 1} has no analysis evidence"
    next
  end

  excerpt = code.text
  exact_excerpt = record.fetch("text", "").include?(excerpt)
  errors << "case excerpt #{index + 1} is not exact source text" unless exact_excerpt
  excerpt_sha = Digest::SHA256.hexdigest(excerpt)
  sha_matches = code["data-excerpt-sha256"] == excerpt_sha
  errors << "case excerpt #{index + 1} sha mismatch" unless sha_matches
  errors << "case excerpt #{index + 1} is not verified in raw source" unless source_membership_verified[key]
  if exact_excerpt && sha_matches && source_membership_verified[key]
    verified_case_excerpts << { key: key, sha256: excerpt_sha, characters: excerpt.length }
  end
end

verified_case_points = 0
document.css("[data-case-point]").each_with_index do |point, index|
  key = point["data-source-key"].to_s
  record = evidence[key]
  quote_text = point.at_css("q[data-case-point-quote]")&.text.to_s
  explanation = point.at_css("[data-case-point-explanation]")&.text.to_s.strip
  errors << "case point #{index + 1} has no analysis evidence" unless record.is_a?(Hash)
  errors << "case point #{index + 1} quote is empty" if quote_text.empty?
  exact_point = record.is_a?(Hash) && !quote_text.empty? && record.fetch("text", "").include?(quote_text)
  if record.is_a?(Hash) && !quote_text.empty?
    errors << "case point #{index + 1} quote is not exact source text" unless exact_point
  end
  errors << "case point #{index + 1} explanation is empty" if explanation.empty?
  errors << "case point #{index + 1} is not verified in raw source" unless source_membership_verified[key]
  verified_case_points += 1 if exact_point && !explanation.empty? && source_membership_verified[key]
end

document.css("[data-chart], [data-derived-insight], [data-zero-finding]").each_with_index do |node, index|
  key = node["data-source-key"].to_s
  resolved = evidence[key] || resolve_analysis_path(analysis, key)
  errors << "numeric evidence node #{index + 1} missing analysis key #{key.inspect}" if key.empty? || resolved.nil?
end

grades = document.css("[data-claim]").each_with_object(Hash.new(0)) do |node, counts|
  counts[node["data-evidence-grade"]] += 1
end
errors << "missing one or more evidence grades" unless %w[A B C D].all? { |grade| grades.fetch(grade, 0).positive? }

checks << { name: "raw_account_ids", count: raw_user_ids.length }
checks << { name: "owner_handles", count: exposed_handles.length }
checks << { name: "raw_source_verified_evidence", count: source_membership_verified.length }
checks << { name: "prompt_quotes", count: quotes.length }
checks << { name: "verified_quotes", count: verified_quotes.length }
checks << { name: "verified_case_metadata", count: verified_case_metadata }
checks << { name: "verified_case_excerpts", count: verified_case_excerpts.length }
checks << { name: "verified_case_points", count: verified_case_points }
checks << { name: "evidence_grades", counts: grades }
checks << { name: "verified_media", count: verified_media.length }
checks << { name: "unavailable_media", count: unavailable_media.length }
checks << { name: "media_manifest", count: media_items.length }
checks << { name: "machine_checked_numeric_leaves", count: numeric_leaf_nodes.length }
checks << { name: "source_manifest", count: source_manifest[:count], sha256: source_manifest[:sha256] }

report = {
  schema_version: 1,
  generated_at: Time.now.utc.iso8601,
  site: options[:site],
  source: options[:source],
  analysis: options[:analysis],
  checks: checks,
  sample_verified_quotes: verified_quotes.first(5),
  errors: errors
}

if options[:report]
  FileUtils.mkdir_p(File.dirname(options[:report]))
  File.write(options[:report], JSON.pretty_generate(report) + "\n")
end

if errors.any?
  warn "HIGGS_INTEGRITY_INVALID count=#{errors.length}"
  errors.each { |error| warn "- #{error}" }
  exit 1
end

puts "HIGGS_INTEGRITY_VALID quotes=#{quotes.length} verified=#{verified_quotes.length} raw_account_ids=0 owner_handles=0"
