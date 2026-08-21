require "csv"
require "fileutils"
require "json"
require "optparse"
require "tempfile"

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
    temporary.close
    File.rename(temporary.path, path)
  ensure
    temporary.close! if temporary
  end
end

repo_root = File.expand_path("..", __dir__)
allowed_output_root = File.realpath(File.join(repo_root, "higgs-data", "_data"))
options = {
  input: File.join(repo_root, "higgs-data", "_data", "analysis.json"),
  json: File.join(repo_root, "higgs-data", "_data", "publishable_analysis.json"),
  tsv: File.join(repo_root, "higgs-data", "_data", "metrics.tsv")
}

OptionParser.new do |parser|
  parser.banner = "Usage: ruby scripts/sanitize_higgs_deep_data.rb [options]"
  parser.on("--input PATH") { |value| options[:input] = value }
  parser.on("--json PATH") { |value| options[:json] = value }
  parser.on("--tsv PATH") { |value| options[:tsv] = value }
end.parse!

input_path = File.realpath(File.expand_path(options[:input], repo_root))
json_path = canonical_target_path(File.expand_path(options[:json], repo_root))
tsv_path = canonical_target_path(File.expand_path(options[:tsv], repo_root))
abort "JSON output must stay under #{allowed_output_root}" unless path_within?(json_path, allowed_output_root)
abort "TSV output must stay under #{allowed_output_root}" unless path_within?(tsv_path, allowed_output_root)
abort "outputs must not overwrite the private input" if [json_path, tsv_path].include?(input_path)
abort "JSON and TSV outputs must be different files" if json_path == tsv_path

analysis = JSON.parse(File.read(input_path))

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

headers = %w[
  project prompt_documents prompt_groups prompt_texts generations outputs
  folders max_depth records unique_generation_ids output_references uploads
  length_total length_min length_mean length_median length_max
]

tsv_payload = CSV.generate(col_sep: "\t") do |tsv|
  tsv << headers
  public_projects.each do |key, project|
    corpus = project.fetch("corpus")
    summary = project.fetch("source_summary")
    lengths = project.fetch("length_stats")
    values = {
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
    tsv << headers.map { |header| values.fetch(header) }
  end
end

json_payload = JSON.pretty_generate(public_analysis) + "\n"
serialized = [json_payload, tsv_payload].join("\n")
forbidden_patterns = {
  "account id" => /user_[A-Za-z0-9_-]+/,
  "absolute source path" => %r{/Users/[^\s\"']+},
  "owner archive path" => %r{owners/[^/]+/}
}
violations = forbidden_patterns.each_with_object([]) do |(label, pattern), matches|
  matches << label if serialized.match?(pattern)
end
owner_handles = analysis.fetch("projects").values.flat_map do |project|
  project.dig("private", "source_files").to_a.flat_map do |entry|
    entry.fetch("path", "").scan(%r{(?:\A|/)owners/([^/]+)/}).flatten
  end
end.uniq
violations << "owner handle" if owner_handles.any? { |handle| !handle.empty? && serialized.include?(handle) }
abort("SANITIZE_FAIL #{violations.join(', ')}") unless violations.empty?

atomic_write(json_path, json_payload)
atomic_write(tsv_path, tsv_payload)

puts "HIGGS_SANITIZE_OK projects=#{public_projects.length} manifest=#{public_analysis.fetch('source_manifest_sha256')}"
