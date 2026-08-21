require "digest"
require "fileutils"
require "json"
require "nokogiri"
require "optparse"
require "tempfile"
require_relative "higgs_html_safety"

def canonical_target_path(path)
  expanded = File.expand_path(path)
  abort "output path must not be a symlink: #{expanded}" if File.symlink?(expanded)
  return File.realpath(expanded) if File.exist?(expanded)

  ancestor = File.dirname(expanded)
  suffix = [File.basename(expanded)]
  until File.exist?(ancestor) || File.symlink?(ancestor)
    parent = File.dirname(ancestor)
    abort "cannot resolve output path: #{expanded}" if parent == ancestor

    suffix.unshift(File.basename(ancestor))
    ancestor = parent
  end
  File.expand_path(File.join(File.realpath(ancestor), *suffix))
end

def path_within?(path, root)
  path == root || path.start_with?(root + File::SEPARATOR)
end

def atomic_write(path, payload)
  temporary = Tempfile.new([".#{File.basename(path)}.", ".tmp"], File.dirname(path))
  begin
    temporary.binmode
    temporary.chmod(0o600)
    temporary.write(payload)
    temporary.flush
    temporary.fsync
    temporary.chmod(0o644)
    temporary.close
    File.rename(temporary.path, path)
  ensure
    temporary.close! if temporary
  end
end

CASE_METADATA_FIELDS = %w[
  character_count tool resolution dimensions aspect generation_count output_count
].freeze

def case_metadata_value(candidate, field)
  return "#{candidate.fetch('width')}x#{candidate.fetch('height')}" if field == "dimensions"

  candidate.fetch(field).to_s
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

def validate_safe_fragment!(root, filename)
  fragment_error = HiggsHtmlSafety.fragment_errors(root).first
  abort("ASSEMBLE_FAIL #{fragment_error} in #{filename}") if fragment_error

  root.css("img[src]").each do |image|
    abort("ASSEMBLE_FAIL non-local image in #{filename}") unless image["src"].start_with?("/higgs-data/media/")
  end
end

repo_root = File.expand_path("..", __dir__)
site_root = File.realpath(File.join(repo_root, "higgs-data"))
private_root = File.realpath(File.join(site_root, "_data"))
options = {
  site: File.join(repo_root, "higgs-data", "index.html"),
  analysis: File.join(repo_root, "higgs-data", "_data", "analysis.json"),
  fragments: File.join(repo_root, "higgs-data", "_data", "fragments"),
  output: nil
}

OptionParser.new do |parser|
  parser.on("--site PATH") { |value| options[:site] = File.expand_path(value, repo_root) }
  parser.on("--analysis PATH") { |value| options[:analysis] = File.expand_path(value, repo_root) }
  parser.on("--fragments PATH") { |value| options[:fragments] = File.expand_path(value, repo_root) }
  parser.on("--output PATH") { |value| options[:output] = File.expand_path(value, repo_root) }
end.parse!

options[:output] ||= options[:site]
options[:site] = File.realpath(options[:site])
options[:analysis] = File.realpath(options[:analysis])
options[:fragments] = File.realpath(options[:fragments])
options[:output] = canonical_target_path(options[:output])
abort("ASSEMBLE_FAIL site input must stay under #{site_root}") unless path_within?(options[:site], site_root)
abort("ASSEMBLE_FAIL analysis input must stay under #{private_root}") unless path_within?(options[:analysis], private_root)
abort("ASSEMBLE_FAIL fragment input must stay under #{private_root}") unless path_within?(options[:fragments], private_root)
abort("ASSEMBLE_FAIL output must stay under #{site_root}") unless path_within?(options[:output], site_root)

panel_contracts = {
  "panel-overview" => ["overview.html", nil, nil],
  "panel-adiliada" => ["adiliada.html", "ADILIADA", "adiliada"],
  "panel-cully" => ["cully.html", "Cully_Hill_Boys", "cully-hill-boys"],
  "panel-hell" => ["hell.html", "Hell_Grind", "hell-grind"],
  "panel-kok" => ["kok.html", "KOK_BORY", "kok-bory"],
  "panel-oneiric" => ["oneiric.html", "ONEIRIC", "oneiric"],
  "panel-zephyr" => ["zephyr.html", "ZEPHYR_Special", "zephyr-special"]
}

analysis = JSON.parse(File.read(options[:analysis], encoding: "UTF-8"))
document = Nokogiri::HTML5.parse(File.read(options[:site], encoding: "UTF-8"))

panel_contracts.each do |panel_id, (filename, project_key, source_slug)|
  fragment_path = File.join(options[:fragments], filename)
  abort("ASSEMBLE_FAIL missing fragment #{fragment_path}") unless File.file?(fragment_path)

  parsed_fragment = Nokogiri::HTML5.fragment(File.read(fragment_path, encoding: "UTF-8"))
  roots = parsed_fragment.element_children
  abort("ASSEMBLE_FAIL #{filename} must have one root") unless roots.length == 1
  replacement = roots.first
  abort("ASSEMBLE_FAIL #{filename} root id mismatch") unless replacement["id"] == panel_id
  validate_safe_fragment!(replacement, filename)

  if project_key
    candidates = analysis.fetch("projects").fetch(project_key).fetch("representative_candidates")
    quotes = replacement.css("[data-prompt-quote]")
    abort("ASSEMBLE_FAIL #{filename} must have six quotes") unless quotes.length == 6

    quotes.each do |quote|
      code = quote.at_css("pre > code[data-prompt-index]")
      abort("ASSEMBLE_FAIL #{filename} quote missing indexed code") unless code
      index = Integer(code["data-prompt-index"], 10)
      candidate = candidates.fetch(index - 1)
      marker = "{{PROMPT:#{project_key}:#{index}}}"
      abort("ASSEMBLE_FAIL #{filename} marker mismatch index=#{index}") unless code.text.strip == marker
      expected_key = "#{source_slug}.quote.#{candidate.fetch('prompt_sha256')[0, 16]}"
      abort("ASSEMBLE_FAIL #{filename} source key mismatch index=#{index}") unless quote["data-source-key"] == expected_key
      code.content = candidate.fetch("text")
    end

    replacement.css("code[data-case-prompt-excerpt]").each do |code|
      index = Integer(code["data-case-prompt-index"], 10)
      start_line = Integer(code["data-case-excerpt-start"], 10)
      line_count = Integer(code["data-case-excerpt-lines"], 10)
      candidate = candidates.fetch(index - 1)
      lines = candidate.fetch("text").lines
      excerpt = lines.slice(start_line, line_count)&.join.to_s
      abort("ASSEMBLE_FAIL empty case excerpt #{filename}:#{index}") if excerpt.strip.empty?

      expected_key = "#{source_slug}.quote.#{candidate.fetch('prompt_sha256')[0, 16]}"
      abort("ASSEMBLE_FAIL case excerpt source key mismatch #{filename}:#{index}") unless code["data-source-key"] == expected_key
      code.content = excerpt
      code["data-excerpt-sha256"] = Digest::SHA256.hexdigest(excerpt)

      case_node = code.ancestors.find { |node| node.element? && node["data-case"] }
      abort("ASSEMBLE_FAIL case excerpt has no case #{filename}:#{index}") unless case_node
      metadata = case_node.at_css("[data-case-metadata]")
      abort("ASSEMBLE_FAIL case excerpt has no metadata #{filename}:#{index}") unless metadata
      metadata.children.remove
      metadata["data-source-key"] = expected_key
      child_name = metadata.name.downcase == "ul" ? "li" : "span"
      CASE_METADATA_FIELDS.each do |field|
        value = case_metadata_value(candidate, field)
        child = Nokogiri::XML::Node.new(child_name, replacement.document)
        child["data-case-meta-field"] = field
        child["data-source-key"] = expected_key
        child["data-case-source-value"] = value
        child.content = case_metadata_display(field, value)
        metadata.add_child(child)
      end
    end
  end

  target = document.at_css("##{panel_id}")
  abort("ASSEMBLE_FAIL missing target #{panel_id}") unless target
  target.replace(replacement)
end

serialized = document.to_html
serialized = serialized.gsub(%r{<pre\b[^>]*>\s*<code\b.*?</code>\s*</pre>}m) do |block|
  block.gsub(/ +(?=\n)/) { |spaces| "&#32;" * spaces.length }
end
verification = Nokogiri::HTML5.parse(serialized)
abort("ASSEMBLE_FAIL expected eight panels") unless verification.css('[role="tabpanel"]').length == 8
abort("ASSEMBLE_FAIL expected 36 prompt quotes") unless verification.css("[data-prompt-quote]").length == 36
abort("ASSEMBLE_FAIL expected 12 case excerpts") unless verification.css("code[data-case-prompt-excerpt]").length == 12

panel_contracts.each do |panel_id, (_filename, project_key, _source_slug)|
  next unless project_key
  candidates = analysis.fetch("projects").fetch(project_key).fetch("representative_candidates")
  verification.css("##{panel_id} [data-prompt-quote]").each do |quote|
    index = Integer(quote.at_css("pre > code")["data-prompt-index"], 10)
    abort("ASSEMBLE_FAIL quote text drift #{panel_id}:#{index}") unless quote.at_css("pre > code").text == candidates.fetch(index - 1).fetch("text")
  end
  verification.css("##{panel_id} code[data-case-prompt-excerpt]").each do |code|
    index = Integer(code["data-case-prompt-index"], 10)
    excerpt = code.text
    expected = candidates.fetch(index - 1).fetch("text")
    abort("ASSEMBLE_FAIL case excerpt drift #{panel_id}:#{index}") unless expected.include?(excerpt)
    abort("ASSEMBLE_FAIL case excerpt sha drift #{panel_id}:#{index}") unless Digest::SHA256.hexdigest(excerpt) == code["data-excerpt-sha256"]
  end
end

atomic_write(options[:output], serialized)
puts "HIGGS_ASSEMBLE_OK panels=7 quotes=36 output=#{options[:output]}"
