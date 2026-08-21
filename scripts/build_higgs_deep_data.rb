#!/usr/bin/env ruby
require "digest"
require "fileutils"
require "json"
require "optparse"
require "pathname"
require "time"

PROJECT_NAMES = {
  "ADILIADA" => "ADILIADA",
  "Cully_Hill_Boys" => "THE CULLY HILL BOYS",
  "Hell_Grind" => "HELL GRIND",
  "KOK_BORY" => "KOK_BORY",
  "ONEIRIC" => "ONEIRIC",
  "ZEPHYR_Special" => "ZEPHYR Special"
}.freeze

KEYWORDS = {
  "camera" => /\bcamera\b|카메라/i,
  "lighting" => /\blight(?:ing)?\b|조명/i,
  "audio" => /\baudio\b|\bsfx\b|sound|오디오|음향/i,
  "dialogue" => /dialog(?:ue)?|대사/i,
  "reference" => /reference|참조|레퍼런스/i,
  "character" => /character|identity|인물|캐릭터/i,
  "negative_constraint" => /\bno\b|\bnever\b|negative|금지|하지 마/i,
  "motion" => /motion|movement|move(?:s|ment)?|움직|동작/i,
  "slow_motion" => /slow[ -]?motion|슬로[ -]?모션/i,
  "photoreal" => /photoreal|realistic|사실적/i,
  "cinematic" => /cinematic|영화적|시네마틱/i,
  "duration" => /\b\d+(?:\.\d+)?\s*(?:s|sec|seconds?)\b|duration|길이/i
}.freeze

BLOCKS = {
  "camera" => /^(?:#+\s*)?(?:camera|shot|lens)\b/im,
  "lighting" => /^(?:#+\s*)?(?:lighting|light)\b/im,
  "audio" => /^(?:#+\s*)?(?:audio|sound|sfx)\b/im,
  "action" => /^(?:#+\s*)?(?:action|motion|movement|performance)\b/im,
  "negative_or_locks" => /^(?:#+\s*)?(?:negative|locks?|constraints?|avoid|no\b)/im,
  "style" => /^(?:#+\s*)?(?:style|look|aesthetic|visual)\b/im,
  "references" => /^(?:#+\s*)?(?:references?|identity|character)\b/im,
  "output_or_time" => /^(?:#+\s*)?(?:output|time|duration|format)\b/im
}.freeze

ZERO_PATTERN_KEYS = %w[
  empty_prompt zero_generation_group zero_output_group missing_tool missing_dimensions
  missing_aspect missing_utc_time missing_folder_path prompt_sha_mismatch
  prompt_character_count_mismatch missing_prompt_text
].freeze

def increment(hash, key, amount = 1)
  hash[key.to_s] = hash.fetch(key.to_s, 0) + amount
end

def numeric(hash, *keys)
  keys.each do |key|
    value = hash[key]
    return value.to_i if value.is_a?(Numeric) || value.to_s.match?(/\A-?\d+\z/)
  end
  0
end

def collection_count(hash, *keys)
  keys.each do |key|
    value = hash[key]
    return value.length if value.is_a?(Array) || value.is_a?(Hash)
    return value.to_i if value.is_a?(Numeric) || value.to_s.match?(/\A-?\d+\z/)
  end
  0
end

def ratio(numerator, denominator)
  return nil if denominator.to_i.zero?

  (numerator.to_f / denominator).round(6)
end

def clean_cell(value)
  value.to_s.gsub("`", "").gsub("<br>", ", ").strip
end

def resolution_parts(value)
  pieces = value.to_s.split("/").map(&:strip)
  dimensions = pieces.find { |piece| piece.match?(/\A\d+x\d+\z/i) }
  width, height = dimensions&.split("x", 2)&.map(&:to_i)
  aspect = pieces.find { |piece| piece.match?(/\A\d+(?:\.\d+)?:\d+(?:\.\d+)?\z/) }
  if aspect.nil? && width.to_i.positive? && height.to_i.positive?
    divisor = width.gcd(height)
    aspect = "#{width / divisor}:#{height / divisor}"
  end
  label = pieces.find { |piece| piece.match?(/\A(?:\d+k|\d+p|\d+x\d+)\z/i) } || "unknown"
  [label, dimensions || "unknown", aspect || "unknown", width, height]
end

def quantile(histogram, percentile)
  total = histogram.values.sum
  return nil if total.zero?

  target = [(total * percentile).ceil, 1].max
  running = 0
  histogram.keys.map(&:to_i).sort.each do |value|
    running += histogram[value.to_s]
    return value if running >= target
  end
  nil
end

def length_stats(histogram)
  count = histogram.values.sum
  return { "count" => 0, "total" => 0, "min" => nil, "max" => nil, "mean" => nil, "p50" => nil, "p90" => nil } if count.zero?

  values = histogram.keys.map(&:to_i)
  total = histogram.sum { |length, occurrences| length.to_i * occurrences }
  {
    "count" => count,
    "total" => total,
    "min" => values.min,
    "max" => values.max,
    "mean" => (total.to_f / count).round(2),
    "p50" => quantile(histogram, 0.50),
    "p90" => quantile(histogram, 0.90)
  }
end

class CandidatePool
  LIMIT = 128

  def initialize
    @items = {}
    @shortest = nil
    @longest = nil
  end

  def add(candidate)
    sha = candidate.fetch("prompt_sha256")
    current = @items[sha]
    @items[sha] = candidate if current.nil? || candidate.fetch("source_path") < current.fetch("source_path")
    @shortest = candidate if @shortest.nil? || candidate.fetch("character_count") < @shortest.fetch("character_count")
    @longest = candidate if @longest.nil? || candidate.fetch("character_count") > @longest.fetch("character_count")
    return unless @items.length > LIMIT

    protected_hashes = [@shortest, @longest].compact.map { |item| item["prompt_sha256"] }
    removable = @items.keys.reject { |key| protected_hashes.include?(key) }.max
    @items.delete(removable) if removable
  end

  def select(count = 12)
    items = @items.values.sort_by { |item| [item.fetch("character_count"), item.fetch("prompt_sha256")] }
    return items if items.length <= count

    indexes = count.times.map { |index| ((index * (items.length - 1)).fdiv(count - 1)).round }.uniq
    indexes.map { |index| items[index] }
  end
end

class ProjectAccumulator
  attr_reader :key, :display_name, :documents, :manifest_entries, :summary_source

  def initialize(key, display_name, source_root)
    @key = key
    @display_name = display_name
    @source_root = source_root
    @documents = 0
    @document_bytes = 0
    @prompt_groups = 0
    @prompt_texts = 0
    @generation_rows = 0
    @output_references = 0
    @length_histogram = {}
    @tools = {}
    @resolutions = {}
    @dimensions = {}
    @aspects = {}
    @months = {}
    @utc_hours = {}
    @blocks = {}
    @keywords = {}
    @folder_depths = {}
    @zero_patterns = Hash.new(0)
    @manifest_entries = []
    @candidate_pool = CandidatePool.new
    @owner_slots = {}
    @summary = nil
    @summary_source = nil
  end

  def prepare_owner_slots(files)
    owners = files.map do |path|
      parts = path.split(File::SEPARATOR)
      parts[parts.index("owners") + 1] if parts.include?("owners")
    end.compact.uniq.sort
    owners.each_with_index { |owner, index| @owner_slots[owner] = format("owner-%03d", index + 1) }
  end

  def owner_metadata(path)
    parts = path.split(File::SEPARATOR)
    owner = parts.include?("owners") ? parts[parts.index("owners") + 1] : "unknown"
    [owner, @owner_slots.fetch(owner, "owner-000")]
  end

  def add_summary(path)
    raw = JSON.parse(File.read(path, encoding: "UTF-8"))
    sha = Digest::SHA256.file(path).hexdigest
    relative = Pathname(path).relative_path_from(Pathname(@source_root)).to_s
    @manifest_entries << { "path" => relative, "sha256" => sha, "bytes" => File.size(path), "kind" => "record_summary" }
    @summary_source = path
    @summary = normalize_summary(raw, File.basename(path))
    @summary["source_file_sha256"] = sha
    @summary["private"] = { "source_path" => path }
  end

  def normalize_summary(raw, filename)
    owners_value = raw["owners"]
    owner_count = if owners_value.is_a?(Array) || owners_value.is_a?(Hash)
                    owners_value.length
                  else
                    numeric(raw, "owners", "owner_count")
                  end
    folder_count = collection_count(raw, "folders", "folders_total")
    {
      "schema_variant" => filename.sub(/\.json\z/, ""),
      "folders" => folder_count,
      "folders_total" => folder_count,
      "folders_indexed" => raw["folders"].is_a?(Hash) ? raw["folders"].length : nil,
      "max_depth" => numeric(raw, "max_depth"),
      "folder_counter" => numeric(raw, "folder_counter", "folder_count_expected"),
      "generations" => numeric(raw, "records", "record_count"),
      "unique_generations" => numeric(raw, "unique_generation_ids", "unique_generation_keys", "unique_folder_generation_keys"),
      "outputs" => numeric(raw, "outputs", "output_references"),
      "unique_outputs" => numeric(raw, "unique_outputs", "unique_output_ids"),
      "uploads" => numeric(raw, "uploads", "uploaded_inputs"),
      "accessible_items" => numeric(raw, "accessible_items"),
      "counter_gap" => numeric(raw, "counter_gap", "remaining_counter_difference"),
      "promptless_generations" => numeric(raw, "promptless", "promptless_records", "promptless_generation_records"),
      "global_prompt_groups" => numeric(raw, "global_prompt_groups", "global_unique_prompt_hashes", "unique_prompt_hashes_global"),
      "owner_prompt_groups" => numeric(raw, "owner_prompt_groups"),
      "archived_prompt_fields" => numeric(raw, "archived_fields", "archived_prompt_field_blocks"),
      "owners" => owner_count,
      "marks" => collection_count(raw, "marks", "mark_count"),
      "field_states" => {
        "folders" => raw.key?("folders") || raw.key?("folders_total") ? "observed" : "missing",
        "uploads" => raw.key?("uploads") || raw.key?("uploaded_inputs") ? "observed" : "missing"
      }
    }
  end

  def add_folder_inventory(path)
    values = {}
    File.foreach(path, encoding: "UTF-8") do |line|
      if (capture = line.match(/^- 전체 폴더: \*\*([\d,]+)개\*\*/))
        values["folders_total"] = capture[1].delete(",").to_i
      end
      if (capture = line.match(/깊이 0[–-](\d+)/))
        values["max_depth"] = capture[1].to_i
      end
      if (capture = line.match(/^- 직접 배치 카운터 합계: \*\*([\d,]+)개\*\*/))
        values["folder_counter"] = capture[1].delete(",").to_i
      end
      if (capture = line.match(/^- 업로드형 이미지·영상: \*\*([\d,]+)개\*\*/))
        values["uploads"] = capture[1].delete(",").to_i
      end
      if (capture = line.match(/^- 접근 가능한 직접 항목: \*\*([\d,]+)개\*\*/))
        values["accessible_items"] = capture[1].delete(",").to_i
      end
      if (capture = line.match(/^- 카운터와의 잔여 차이: \*\*([\d,]+)개\*\*/))
        values["counter_gap"] = capture[1].delete(",").to_i
      end
      break if line.start_with?("| 경로")
    end
    required = %w[folders_total max_depth folder_counter uploads accessible_items counter_gap]
    missing = required.reject { |key| values.key?(key) }
    abort "unrecognized folder inventory schema: #{path} missing #{missing.join(', ')}" unless missing.empty?

    sha = Digest::SHA256.file(path).hexdigest
    relative = Pathname(path).relative_path_from(Pathname(@source_root)).to_s
    @manifest_entries << { "path" => relative, "sha256" => sha, "bytes" => File.size(path), "kind" => "folder_inventory" }
    @summary["folders_indexed"] = @summary["folders"]
    @summary["folders"] = values["folders_total"]
    @summary["folders_total"] = values["folders_total"]
    @summary["max_depth"] = values["max_depth"]
    @summary["folder_counter"] = values["folder_counter"]
    @summary["uploads"] = values["uploads"]
    @summary["accessible_items"] = values["accessible_items"]
    @summary["counter_gap"] = values["counter_gap"]
    @summary["field_states"]["folders"] = "canonical_inventory"
    @summary["field_states"]["uploads"] = "canonical_inventory"
    @summary["private"]["folder_inventory_source_path"] = path
    @summary["folder_inventory_sha256"] = sha
  end

  def add_document(path)
    @documents += 1
    @document_bytes += File.size(path)
    owner_path, owner_slot = owner_metadata(path)
    relative = Pathname(path).relative_path_from(Pathname(@source_root)).to_s
    digest = Digest::SHA256.new
    has_record_comments = false
    upcoming_group = {}
    group = nil
    field_info = nil
    fence = nil
    buffer = +""

    File.open(path, "rb") do |io|
      io.each_line do |raw_line|
        digest.update(raw_line)
        line = raw_line.force_encoding("UTF-8").scrub

        if fence
          if line.strip == fence
            text = buffer.delete_suffix("\n").delete_suffix("\r")
            consume_prompt(text, field_info || {}, group || {}, path, relative, owner_path, owner_slot)
            fence = nil
            buffer = +""
            field_info = nil
          else
            buffer << line
          end
          next
        end

        if (match = line.match(/<!--\s*[A-Z]+_GROUP\s+(\{.*\})\s*-->/))
          upcoming_group = JSON.parse(match[1])
          next
        end

        if (match = line.match(/^##\s+\d+\.\s+Prompt Group\s+`([^`]+)`/))
          @prompt_groups += 1
          group = {
            "group_id" => match[1],
            "object_sha256" => upcoming_group["prompt_hash"],
            "generation_count" => 0,
            "output_count" => 0,
            "first_tool" => nil,
            "first_resolution" => nil,
            "first_dimensions" => nil,
            "first_aspect" => nil,
            "first_width" => nil,
            "first_height" => nil,
            "first_time" => nil,
            "first_folder" => nil
          }
          upcoming_group = {}
          next
        end

        if (match = line.match(/<!--\s*[A-Z]+_RECORD\s+(\{.*\})\s*-->/))
          has_record_comments = true
          record = JSON.parse(match[1])
          consume_record(record["tool"], record["resolution"], record["created_at"], record.fetch("outputs", []).length, group)
          next
        end

        if (match = line.match(/<!--\s*[A-Z]+_FIELD\s+(\{.*\})\s*-->/))
          data = JSON.parse(match[1])
          field_info = data["path"] == "prompt" ? data : nil
          next
        end

        if line.match?(/^###\s+`prompt`\s*$/)
          field_info = { "path" => "prompt" }
          next
        end

        if field_info
          field_info["chars"] ||= Regexp.last_match(1).to_i if line.match(/^- 문자 수:\s*(\d+)/)
          field_info["sha256"] ||= Regexp.last_match(1) if line.match(/^- SHA-256:\s*`([0-9a-f]{64})`/)
          if (match = line.match(/^(`{3,})(?:text)?\s*$/))
            fence = match[1]
            buffer = +""
            next
          end
        end

        next unless line.start_with?("|")

        cells = line.split("|", -1).map(&:strip)
        generation_id = clean_cell(cells[1])
        next unless generation_id.match?(/\A[0-9a-f-]{36}\z/i)

        folder = clean_cell(cells[2])
        if group
          group["first_folder"] ||= folder
          consume_folder(folder)
        end
        next if has_record_comments

        output_count = clean_cell(cells[6]).scan(/×(\d+)/).flatten.map(&:to_i).sum
        consume_record(clean_cell(cells[3]), clean_cell(cells[4]), clean_cell(cells[5]), output_count, group)
      end
    end

    sha = digest.hexdigest
    @manifest_entries << { "path" => relative, "sha256" => sha, "bytes" => File.size(path), "kind" => "prompt_archive" }
  end

  def consume_record(tool, resolution, utc_time, output_count, group)
    @generation_rows += 1
    @output_references += output_count.to_i
    label, dimensions, aspect, width, height = resolution_parts(resolution)
    increment(@tools, tool.to_s.empty? ? "unknown" : tool)
    increment(@resolutions, label)
    increment(@dimensions, dimensions)
    increment(@aspects, aspect)
    if (match = utc_time.to_s.match(/\A(\d{4}-\d{2})-\d{2}T(\d{2})/))
      increment(@months, match[1])
      increment(@utc_hours, match[2])
    end
    return unless group

    group["generation_count"] += 1
    group["output_count"] += output_count.to_i
    group["first_tool"] ||= tool
    group["first_resolution"] ||= label
    group["first_dimensions"] ||= dimensions
    group["first_aspect"] ||= aspect
    group["first_width"] ||= width
    group["first_height"] ||= height
    group["first_time"] ||= utc_time
  end

  def consume_folder(folder)
    depth = folder.to_s.split("/").map(&:strip).reject(&:empty?).length
    increment(@folder_depths, depth)
  end

  def consume_prompt(text, field_info, group, source_path, relative, owner_path, owner_slot)
    @prompt_texts += 1
    actual_length = text.length
    length = field_info["chars"] ? field_info["chars"].to_i : actual_length
    sha = Digest::SHA256.hexdigest(text)
    declared_sha = field_info["sha256"]
    declared_chars = field_info["chars"]
    increment(@length_histogram, length)
    increment(@zero_patterns, "empty_prompt") if length.zero?
    increment(@zero_patterns, "zero_generation_group") if group.fetch("generation_count", 0).zero?
    increment(@zero_patterns, "zero_output_group") if group.fetch("output_count", 0).zero?
    increment(@zero_patterns, "missing_tool") if group["first_tool"].to_s.empty?
    increment(@zero_patterns, "missing_dimensions") if [nil, "unknown"].include?(group["first_dimensions"])
    increment(@zero_patterns, "missing_aspect") if [nil, "unknown"].include?(group["first_aspect"])
    increment(@zero_patterns, "missing_utc_time") if group["first_time"].to_s.empty?
    increment(@zero_patterns, "missing_folder_path") if group["first_folder"].to_s.empty?
    increment(@zero_patterns, "prompt_sha_mismatch") if declared_sha && declared_sha != sha
    increment(@zero_patterns, "prompt_character_count_mismatch") if declared_chars && declared_chars.to_i != actual_length
    KEYWORDS.each { |name, pattern| increment(@keywords, name) if text.match?(pattern) }
    BLOCKS.each { |name, pattern| increment(@blocks, name) if text.match?(pattern) }
    return if text.strip.empty?

    sanitized_document = File.join(owner_slot, File.basename(source_path))
    @candidate_pool.add(
      "text" => text,
      "text_truncated" => false,
      "character_count" => length,
      "prompt_sha256" => sha,
      "declared_prompt_sha256" => declared_sha,
      "source_path" => source_path,
      "source_relative_path" => relative,
      "source_file_sha256" => nil,
      "group_id" => group["group_id"],
      "tool" => group["first_tool"] || "unknown",
      "resolution" => group["first_resolution"] || "unknown",
      "width" => group["first_width"],
      "height" => group["first_height"],
      "aspect" => group["first_aspect"] || "unknown",
      "utc_time" => group["first_time"],
      "folder_path" => group["first_folder"],
      "generation_count" => group.fetch("generation_count", 0),
      "output_count" => group.fetch("output_count", 0),
      "display" => {
        "project" => @display_name,
        "owner_slot" => owner_slot,
        "source_document" => sanitized_document,
        "folder_depth" => group["first_folder"].to_s.split("/").reject(&:empty?).length
      },
      "private" => { "owner_path" => owner_path }
    )
  end

  def finish
    hashes_by_path = @manifest_entries.to_h { |entry| [File.join(@source_root, entry["path"]), entry["sha256"]] }
    candidates = @candidate_pool.select(12)
    @zero_patterns["missing_prompt_text"] = @prompt_groups - @prompt_texts
    ZERO_PATTERN_KEYS.each { |key| @zero_patterns[key] = @zero_patterns.fetch(key, 0) }
    candidates.each { |candidate| candidate["source_file_sha256"] = hashes_by_path.fetch(candidate["source_path"]) }
    summary = @summary || {
      "schema_variant" => "missing_record_summary",
      "folders" => 0, "folder_counter" => 0, "generations" => 0, "unique_generations" => 0,
      "outputs" => 0, "unique_outputs" => 0, "uploads" => 0, "accessible_items" => 0,
      "counter_gap" => 0, "promptless_generations" => 0, "global_prompt_groups" => 0,
      "owner_prompt_groups" => 0, "archived_prompt_fields" => 0, "owners" => 0, "marks" => 0,
      "private" => { "source_path" => nil }
    }
    summary["derived_ratios"] = {
      "outputs_per_generation" => ratio(summary["outputs"], summary["generations"]),
      "uploads_per_generation" => ratio(summary["uploads"], summary["generations"]),
      "promptless_generation_rate" => ratio(summary["promptless_generations"], summary["generations"]),
      "archive_groups_per_generation" => ratio(@prompt_groups, summary["generations"]),
      "parsed_outputs_per_generation" => ratio(@output_references, @generation_rows)
    }
    {
      "display_name" => @display_name,
      "source_summary" => summary,
      "corpus" => {
        "prompt_documents" => @documents,
        "prompt_document_bytes" => @document_bytes,
        "prompt_groups" => @prompt_groups,
        "prompt_texts" => @prompt_texts,
        "parsed_generation_rows" => @generation_rows,
        "parsed_output_references" => @output_references
      },
      "length_stats" => length_stats(@length_histogram),
      "distributions" => {
        "tools" => @tools.sort.to_h,
        "resolutions" => @resolutions.sort.to_h,
        "dimensions" => @dimensions.sort.to_h,
        "aspects" => @aspects.sort.to_h,
        "utc_months" => @months.sort.to_h,
        "utc_hours" => @utc_hours.sort.to_h,
        "prompt_blocks" => @blocks.sort.to_h,
        "keywords" => @keywords.sort.to_h,
        "folder_depths" => @folder_depths.sort_by { |key, _| key.to_i }.to_h
      },
      "zero_patterns" => @zero_patterns.sort.to_h,
      "representative_candidates" => candidates,
      "private" => {
        "project_source_path" => File.join(@source_root, @key),
        "length_histogram" => @length_histogram.sort_by { |key, _| key.to_i }.to_h,
        "source_files" => @manifest_entries.sort_by { |entry| entry["path"] }
      }
    }
  end
end

options = {}
OptionParser.new do |parser|
  parser.banner = "Usage: build_higgs_deep_data.rb --source PATH --output PATH"
  parser.on("--source PATH", "Higgsfield analysis source root") { |value| options[:source] = File.expand_path(value) }
  parser.on("--output PATH", "Destination JSON file") { |value| options[:output] = File.expand_path(value) }
end.parse!(ARGV)

abort "missing required --source PATH" unless options[:source]
abort "missing required --output PATH" unless options[:output]
abort "source directory does not exist: #{options[:source]}" unless Dir.exist?(options[:source])

source_root = options[:source]
projects = {}
all_manifest_entries = []

PROJECT_NAMES.each do |project_key, display_name|
  project_root = File.join(source_root, project_key)
  abort "missing project directory: #{project_root}" unless Dir.exist?(project_root)

  prompt_files = Dir.glob(File.join(project_root, "**", "{prompts.md,prompts_part_*.md}"), File::FNM_EXTGLOB).select { |path| path.include?("#{File::SEPARATOR}owners#{File::SEPARATOR}") }.sort
  accumulator = ProjectAccumulator.new(project_key, display_name, source_root)
  accumulator.prepare_owner_slots(prompt_files)
  summary_files = Dir.glob(File.join(project_root, "ULW_Research_Log", "*record-summary.json")).sort
  abort "multiple record summaries for #{project_key}: #{summary_files.join(', ')}" if summary_files.length > 1
  accumulator.add_summary(summary_files.first) if summary_files.first
  inventory = File.join(project_root, "#{project_key}_FOLDER_INVENTORY.md")
  accumulator.add_folder_inventory(inventory) if project_key == "Cully_Hill_Boys" && File.file?(inventory)
  prompt_files.each { |path| accumulator.add_document(path) }
  project = accumulator.finish
  projects[project_key] = project
  all_manifest_entries.concat(project.fetch("private").fetch("source_files"))
end

manifest_payload = all_manifest_entries.sort_by { |entry| entry.fetch("path") }.map do |entry|
  [entry.fetch("path"), entry.fetch("sha256"), entry.fetch("bytes"), entry.fetch("kind")].join("\0")
end.join("\n")

evidence = {}
projects.each do |project_key, project|
  slug = project_key.downcase.tr("_", "-")
  project.fetch("representative_candidates").each do |candidate|
    key = "#{slug}.quote.#{candidate.fetch('prompt_sha256')[0, 16]}"
    suffix = 2
    while evidence.key?(key)
      key = "#{slug}.quote.#{candidate.fetch('prompt_sha256')[0, 16]}.#{suffix}"
      suffix += 1
    end
    evidence[key] = candidate
  end
end

global_distributions = Hash.new { |hash, key| hash[key] = Hash.new(0) }
global_zero = Hash.new(0)
global_length_histogram = Hash.new(0)
projects.each_value do |project|
  project.dig("private", "length_histogram").each { |length, count| global_length_histogram[length] += count }
  project.fetch("distributions").each do |name, distribution|
    distribution.each { |key, value| global_distributions[name][key] += value }
  end
  project.fetch("zero_patterns").each { |key, value| global_zero[key] += value }
end

global_corpus = {
  "prompt_documents" => projects.values.sum { |project| project.dig("corpus", "prompt_documents") },
  "prompt_document_bytes" => projects.values.sum { |project| project.dig("corpus", "prompt_document_bytes") },
  "prompt_groups" => projects.values.sum { |project| project.dig("corpus", "prompt_groups") },
  "prompt_texts" => projects.values.sum { |project| project.dig("corpus", "prompt_texts") },
  "parsed_generation_rows" => projects.values.sum { |project| project.dig("corpus", "parsed_generation_rows") },
  "parsed_output_references" => projects.values.sum { |project| project.dig("corpus", "parsed_output_references") },
  "summary_generations" => projects.values.sum { |project| project.dig("source_summary", "generations") },
  "summary_outputs" => projects.values.sum { |project| project.dig("source_summary", "outputs") },
  "summary_uploads" => projects.values.sum { |project| project.dig("source_summary", "uploads") },
  "summary_folders" => projects.values.sum { |project| project.dig("source_summary", "folders") }
}
global_corpus["derived_ratios"] = {
  "outputs_per_generation" => ratio(global_corpus["summary_outputs"], global_corpus["summary_generations"]),
  "uploads_per_generation" => ratio(global_corpus["summary_uploads"], global_corpus["summary_generations"]),
  "prompt_groups_per_generation" => ratio(global_corpus["prompt_groups"], global_corpus["summary_generations"])
}

result = {
  "schema_version" => "higgs-deep-data-v2",
  "generated_at" => Time.now.utc.iso8601,
  "source_root" => source_root,
  "source_manifest_sha256" => Digest::SHA256.hexdigest(manifest_payload),
  "global" => {
    "corpus" => global_corpus,
    "length_stats" => length_stats(global_length_histogram),
    "distributions" => global_distributions.transform_values { |distribution| distribution.sort.to_h },
    "zero_patterns" => global_zero.sort.to_h
  },
  "projects" => projects,
  "evidence" => evidence
}

display_json = JSON.generate(projects.transform_values { |project| project.reject { |key, _| key == "private" }.merge("representative_candidates" => project["representative_candidates"].map { |candidate| candidate.fetch("display") }) })
abort "raw user ID leaked into display fields" if display_json.match?(/user_[A-Za-z0-9]+/)

FileUtils.mkdir_p(File.dirname(options[:output]))
temporary = "#{options[:output]}.tmp-#{Process.pid}"
File.open(temporary, "wb") { |file| file.write(JSON.pretty_generate(result)); file.write("\n") }
File.rename(temporary, options[:output])

warn "HIGGS_DEEP_DATA_OK projects=#{projects.length} documents=#{global_corpus['prompt_documents']} groups=#{global_corpus['prompt_groups']} evidence=#{evidence.length} manifest=#{result['source_manifest_sha256']}"
