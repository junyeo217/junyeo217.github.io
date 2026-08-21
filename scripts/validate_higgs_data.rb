require "digest"
require "json"
require "nokogiri"

repo_root = File.expand_path("..", __dir__)
target = ARGV[0] || File.join(repo_root, "higgs-data", "index.html")
errors = []

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

if errors.any?
  warn "HIGGS_DATA_INVALID count=#{errors.length}"
  errors.each { |error| warn "- #{error}" }
  exit 1
end

puts "HIGGS_DATA_VALID panels=8 projects=6 evidence_labels=4 contacts=4 unique_ids=#{ids.length}"
