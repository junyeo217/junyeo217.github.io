require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"

class HiggsAssemblerSecurityTest < Minitest::Test
  PROJECTS = {
    "ADILIADA" => ["adiliada", "adiliada"],
    "Cully_Hill_Boys" => ["cully", "cully-hill-boys"],
    "Hell_Grind" => ["hell", "hell-grind"],
    "KOK_BORY" => ["kok", "kok-bory"],
    "ONEIRIC" => ["oneiric", "oneiric"],
    "ZEPHYR_Special" => ["zephyr", "zephyr-special"]
  }.freeze

  def test_cli_assembles_the_safe_synthetic_fixture
    Dir.mktmpdir("higgs-assembler-safe-") do |root|
      build_fixture(root, "")
      output = File.join(root, "higgs-data", "safe-output.html")
      stdout, stderr, status = run_assembler(root, output)
      assert status.success?, stdout + stderr
      assert_includes stdout, "HIGGS_ASSEMBLE_OK"
      assert File.file?(output)
    end
  end

  def test_cli_rejects_hostile_fragments_without_writing_output
    {
      '<img src="/higgs-data/media/poster.jpg" attributionsrc="https://attacker.invalid/register">' => "attributionsrc",
      '<svg><rect fill="url(https://attacker.invalid/paint.svg#pattern)"></rect></svg>' => "external resource IRI",
      '<style>@import url("https://attacker.invalid/a.css");</style>' => "unsafe element style"
    }.each_with_index do |(payload, expected), index|
      Dir.mktmpdir("higgs-assembler-hostile-") do |root|
        build_fixture(root, payload)
        output = File.join(root, "higgs-data", "probe-#{index}.html")
        stdout, stderr, status = run_assembler(root, output)
        refute status.success?
        assert_includes stdout + stderr, expected
        refute File.exist?(output)
      end
    end
  end

  def test_cli_rejects_private_analysis_output_without_overwrite
    Dir.mktmpdir("higgs-assembler-overlap-") do |root|
      build_fixture(root, "")
      analysis = File.join(root, "higgs-data", "_data", "analysis.json")
      before = Digest::SHA256.file(analysis).hexdigest
      stdout, stderr, status = run_assembler(root, analysis)
      refute status.success?
      assert_includes stdout + stderr, "direct HTML child"
      assert_equal before, Digest::SHA256.file(analysis).hexdigest
    end
  end

  private

  def run_assembler(root, output)
    Open3.capture3(
      RbConfig.ruby,
      File.join(root, "scripts", "assemble_higgs_data.rb"),
      "--output",
      output,
      chdir: root
    )
  end

  def build_fixture(root, overview_payload)
    scripts = File.join(root, "scripts")
    site = File.join(root, "higgs-data")
    fragments = File.join(site, "_data", "fragments")
    FileUtils.mkdir_p([scripts, fragments])
    FileUtils.cp(File.expand_path("../scripts/assemble_higgs_data.rb", __dir__), scripts)
    FileUtils.cp(File.expand_path("../scripts/higgs_html_safety.rb", __dir__), scripts)

    panel_ids = ["overview"] + PROJECTS.values.map(&:first) + ["author"]
    panels = panel_ids.map { |id| %(<section id="panel-#{id}" role="tabpanel"></section>) }.join
    File.write(File.join(site, "index.html"), "<!doctype html><html><body>#{panels}</body></html>")
    File.write(File.join(fragments, "overview.html"), %(<section id="panel-overview" role="tabpanel">#{overview_payload}</section>))

    analysis = { "projects" => {} }
    PROJECTS.each do |project_key, (filename, slug)|
      candidates = (1..6).map { |index| candidate(project_key, index) }
      analysis["projects"][project_key] = { "representative_candidates" => candidates }
      quotes = candidates.each_with_index.map do |item, offset|
        index = offset + 1
        key = "#{slug}.quote.#{item.fetch('prompt_sha256')[0, 16]}"
        %(<article data-prompt-quote="" data-source-key="#{key}"><pre><code data-prompt-index="#{index}">{{PROMPT:#{project_key}:#{index}}}</code></pre></article>)
      end.join
      cases = candidates.first(2).each_with_index.map do |item, offset|
        index = offset + 1
        key = "#{slug}.quote.#{item.fetch('prompt_sha256')[0, 16]}"
        %(<article data-case=""><ul data-case-metadata=""></ul><code data-case-prompt-excerpt="" data-case-prompt-index="#{index}" data-case-excerpt-start="0" data-case-excerpt-lines="1" data-source-key="#{key}"></code></article>)
      end.join
      File.write(File.join(fragments, "#{filename}.html"), %(<section id="panel-#{filename}" role="tabpanel">#{quotes}#{cases}</section>))
    end
    File.write(File.join(site, "_data", "analysis.json"), JSON.generate(analysis))
  end

  def candidate(project_key, index)
    text = "#{project_key} synthetic prompt #{index}\nsecond line\n"
    {
      "text" => text,
      "prompt_sha256" => Digest::SHA256.hexdigest(text),
      "character_count" => text.length,
      "tool" => "synthetic",
      "resolution" => "720p",
      "width" => 1280,
      "height" => 720,
      "aspect" => "16:9",
      "generation_count" => 1,
      "output_count" => 1
    }
  end
end
