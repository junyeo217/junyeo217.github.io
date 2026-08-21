require "json"
require "nokogiri"
require "optparse"

repo_root = File.expand_path("..", __dir__)
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

panel_contracts.each do |panel_id, (_filename, project_key, _source_slug)|
  next unless project_key
  candidates = analysis.fetch("projects").fetch(project_key).fetch("representative_candidates")
  verification.css("##{panel_id} [data-prompt-quote]").each do |quote|
    index = Integer(quote.at_css("pre > code")["data-prompt-index"], 10)
    abort("ASSEMBLE_FAIL quote text drift #{panel_id}:#{index}") unless quote.at_css("pre > code").text == candidates.fetch(index - 1).fetch("text")
  end
end

File.write(options[:output], serialized)
puts "HIGGS_ASSEMBLE_OK panels=7 quotes=36 output=#{options[:output]}"
