require "csv"
require "json"
require "optparse"

options = {
  input: "higgs-data/_data/analysis.json",
  json: "higgs-data/_data/publishable_analysis.json",
  tsv: "higgs-data/_data/metrics.tsv"
}

OptionParser.new do |parser|
  parser.banner = "Usage: ruby scripts/sanitize_higgs_deep_data.rb [options]"
  parser.on("--input PATH") { |value| options[:input] = value }
  parser.on("--json PATH") { |value| options[:json] = value }
  parser.on("--tsv PATH") { |value| options[:tsv] = value }
end.parse!

analysis = JSON.parse(File.read(options[:input]))

def public_candidate(candidate)
  candidate.reject do |key, _value|
    %w[text source_path source_relative_path group_id folder_path private].include?(key)
  end
end

def without_private(value)
  case value
  when Hash
    value.each_with_object({}) do |(key, child), result|
      result[key] = without_private(child) unless key == "private"
    end
  when Array
    value.map { |child| without_private(child) }
  else
    value
  end
end

public_projects = analysis.fetch("projects").transform_values do |project|
  {
    "display_name" => project.fetch("display_name"),
    "source_summary" => without_private(project.fetch("source_summary")),
    "corpus" => project.fetch("corpus"),
    "length_stats" => project.fetch("length_stats"),
    "distributions" => project.fetch("distributions"),
    "zero_patterns" => project.fetch("zero_patterns"),
    "representative_candidates" => project.fetch("representative_candidates").map do |candidate|
      public_candidate(candidate)
    end
  }
end

public_analysis = {
  "schema_version" => analysis.fetch("schema_version"),
  "generated_at" => analysis.fetch("generated_at"),
  "source_manifest_sha256" => analysis.fetch("source_manifest_sha256"),
  "privacy_contract" => {
    "account_identifiers" => "omitted",
    "absolute_source_paths" => "omitted",
    "prompt_text" => "omitted from this summary; exact excerpts are selected from the private ignored analysis file"
  },
  "global" => analysis.fetch("global"),
  "projects" => public_projects
}

File.write(options[:json], JSON.pretty_generate(public_analysis) + "\n")

headers = %w[
  project prompt_documents prompt_groups prompt_texts generations outputs
  folders max_depth records unique_generation_ids output_references uploads
  length_total length_min length_mean length_median length_max
]

CSV.open(options[:tsv], "w", col_sep: "\t", write_headers: true, headers: headers) do |tsv|
  public_projects.each do |key, project|
    corpus = project.fetch("corpus")
    summary = project.fetch("source_summary")
    lengths = project.fetch("length_stats")
    tsv << {
      "project" => key,
      "prompt_documents" => corpus.fetch("prompt_documents"),
      "prompt_groups" => corpus.fetch("prompt_groups"),
      "prompt_texts" => corpus.fetch("prompt_texts"),
      "generations" => corpus.fetch("parsed_generation_rows"),
      "outputs" => corpus.fetch("parsed_output_references"),
      "folders" => summary.fetch("folders"),
      "max_depth" => summary.fetch("max_depth"),
      "records" => summary.fetch("generations"),
      "unique_generation_ids" => summary.fetch("unique_generations"),
      "output_references" => summary.fetch("outputs"),
      "uploads" => summary.fetch("uploads"),
      "length_total" => lengths.fetch("total"),
      "length_min" => lengths.fetch("min"),
      "length_mean" => lengths.fetch("mean"),
      "length_median" => lengths.fetch("p50"),
      "length_max" => lengths.fetch("max")
    }
  end
end

serialized = JSON.generate(public_analysis)
forbidden_patterns = {
  "account id" => /user_[A-Za-z0-9_-]+/,
  "absolute source path" => %r{/Users/[^\s\"']+},
  "owner archive path" => %r{owners/[^/]+/}
}
violations = forbidden_patterns.each_with_object([]) do |(label, pattern), matches|
  matches << label if serialized.match?(pattern)
end
abort("SANITIZE_FAIL #{violations.join(', ')}") unless violations.empty?

puts "HIGGS_SANITIZE_OK projects=#{public_projects.length} manifest=#{public_analysis.fetch('source_manifest_sha256')}"
