require "minitest/autorun"
require "nokogiri"
require "open3"
require "rbconfig"
require "tempfile"
require_relative "../scripts/higgs_html_safety"

class HiggsHtmlSafetyTest < Minitest::Test
  def test_rejects_entity_decoded_control_character_in_executable_scheme
    fragment = Nokogiri::HTML5.fragment('<a href="java&#10;script:alert(1)">unsafe</a>')
    href = fragment.at_css("a")["href"]

    assert_equal "executable URL", HiggsHtmlSafety.url_attribute_error("href", href)
  end

  def test_rejects_every_srcset_until_a_local_candidate_parser_is_required
    assert_equal "srcset attribute",
      HiggsHtmlSafety.url_attribute_error("srcset", "/higgs-data/media/poster.jpg 1x, https://attacker.invalid/tracker.png 2x")
    assert_equal "srcset attribute",
      HiggsHtmlSafety.url_attribute_error("srcset", "/higgs-data/media/poster.jpg 1x")
  end

  def test_rejects_supported_executable_schemes
    assert_equal "executable URL", HiggsHtmlSafety.url_attribute_error("href", " javascript:alert(1)")
    assert_equal "executable URL", HiggsHtmlSafety.url_attribute_error("href", "vbscript:msgbox(1)")
    assert_equal "executable URL", HiggsHtmlSafety.url_attribute_error("href", "data:text/html,<script>alert(1)</script>")
  end

  def test_allows_expected_navigation_and_local_media_urls
    assert_nil HiggsHtmlSafety.url_attribute_error("href", "https://higgsfield.ai/project/example")
    assert_nil HiggsHtmlSafety.url_attribute_error("href", "mailto:junyeo.ai@gmail.com")
    assert_nil HiggsHtmlSafety.url_attribute_error("src", "/higgs-data/media/poster.jpg")
  end

  def test_rejects_executable_fragment_attributes
    assert_equal "event attribute onclick", HiggsHtmlSafety.attribute_error("section", "onclick", "alert(1)")
    assert_equal "srcdoc attribute", HiggsHtmlSafety.attribute_error("section", "srcdoc", "<script>alert(1)</script>")
    assert_equal "unsafe inline style", HiggsHtmlSafety.attribute_error("section", "style", "background:url(https://attacker.invalid/a.png)")
    assert_equal "unsafe inline style", HiggsHtmlSafety.attribute_error("section", "style", 'background-image:image-set("https://attacker.invalid/a.png" 2x)')
    assert_equal "unsupported resource attribute ping", HiggsHtmlSafety.attribute_error("a", "ping", "https://attacker.invalid/ping")
    assert_equal "unsupported resource attribute lowsrc", HiggsHtmlSafety.attribute_error("img", "lowsrc", "https://attacker.invalid/preview.png")
    assert_equal "unsupported resource attribute attributionsrc", HiggsHtmlSafety.attribute_error("img", "attributionsrc", "https://attacker.invalid/register")
  end

  def test_rejects_external_resource_loads_beyond_img_src
    assert_equal "non-local resource URL", HiggsHtmlSafety.attribute_error("image", "href", "https://attacker.invalid/tracker.png")
    assert_equal "non-local resource URL", HiggsHtmlSafety.attribute_error("feImage", "xlink:href", "https://attacker.invalid/filter.png")
    assert_equal "non-local resource URL", HiggsHtmlSafety.attribute_error("video", "poster", "https://attacker.invalid/poster.png")
    assert_equal "non-local resource URL", HiggsHtmlSafety.attribute_error("source", "src", "https://attacker.invalid/media.mp4")
    assert_equal "resource background attribute", HiggsHtmlSafety.attribute_error("table", "background", "https://attacker.invalid/tile.png")
  end

  def test_allows_local_media_and_same_document_svg_references
    assert_nil HiggsHtmlSafety.attribute_error("img", "src", "/higgs-data/media/poster.jpg")
    assert_nil HiggsHtmlSafety.attribute_error("video", "poster", "/higgs-data/media/poster.jpg")
    assert_nil HiggsHtmlSafety.attribute_error("use", "href", "#chart-symbol")
    assert_nil HiggsHtmlSafety.attribute_error("a", "href", "https://higgsfield.ai/project/example")
    assert_nil HiggsHtmlSafety.attribute_error("script", "src", "/higgs-data/higgs-data.js?v=1")
  end

  def test_fragment_traversal_rejects_external_svg_presentation_iris
    fragment = Nokogiri::HTML5.fragment(<<~HTML)
      <section id="panel-overview">
        <svg>
          <rect fill="url(https://attacker.invalid/fill.svg#paint)"></rect>
          <g filter="url(https://attacker.invalid/filter.svg#blur)"></g>
          <path mask="url(https://attacker.invalid/mask.svg#cutout)"></path>
        </svg>
      </section>
    HTML

    errors = HiggsHtmlSafety.fragment_errors(fragment.element_children.first)
    assert_equal ["external resource IRI", "external resource IRI", "external resource IRI"], errors
  end

  def test_svg_presentation_iris_allow_only_plain_values_and_local_fragments
    assert_nil HiggsHtmlSafety.attribute_error("rect", "fill", "#c7ff4a")
    assert_nil HiggsHtmlSafety.attribute_error("rect", "fill", "url(#study-gradient)")
    assert_nil HiggsHtmlSafety.attribute_error("g", "filter", "none")
    assert_equal "external resource IRI", HiggsHtmlSafety.attribute_error("rect", "fill", "url(data:image/svg+xml,unsafe)")
    assert_equal "external resource IRI", HiggsHtmlSafety.attribute_error("rect", "fill", "u/**/rl(https://attacker.invalid/a.svg)")
    assert_equal "external resource IRI", HiggsHtmlSafety.attribute_error("rect", "fill", "u\\72l(https://attacker.invalid/a.svg)")
  end

  def test_rejects_forbidden_fragment_elements
    %w[script iframe object embed applet frame frameset fencedframe portal form base link meta style foreignObject animate animateMotion animateTransform set].each do |name|
      assert_match(/unsafe element/, HiggsHtmlSafety.fragment_element_error(name))
    end
  end

  def test_allows_non_executable_fragment_markup
    assert_nil HiggsHtmlSafety.fragment_element_error("section")
    assert_nil HiggsHtmlSafety.attribute_error("section", "class", "study-card")
    assert_nil HiggsHtmlSafety.attribute_error("span", "style", "--hd-chart-value: 42.125%")
  end

  def test_current_public_document_passes_shared_final_policy
    document = Nokogiri::HTML5.parse(File.read(File.expand_path("../higgs-data/index.html", __dir__), encoding: "UTF-8"))

    assert_empty HiggsHtmlSafety.final_document_errors(document)
  end

  def test_shared_final_policy_rejects_untrusted_elements_and_registration_urls
    document = Nokogiri::HTML5.parse(<<~HTML)
      <!doctype html><html><head><style>@import url("https://attacker.invalid/a.css");</style></head>
      <body><applet code="https://attacker.invalid/a.class"></applet>
      <img src="/higgs-data/media/poster.jpg" attributionsrc="https://attacker.invalid/register"></body></html>
    HTML

    errors = HiggsHtmlSafety.final_document_errors(document)
    assert_includes errors, "unsafe final element style"
    assert_includes errors, "unsafe final element applet"
    assert_includes errors, "unsupported resource attribute attributionsrc on img"
  end

  def test_actual_validator_rejects_hostile_final_html
    source = File.read(File.expand_path("../higgs-data/index.html", __dir__), encoding: "UTF-8")
    hostile = source.sub("</head>", '<style>@import url("https://attacker.invalid/a.css");</style></head>')
      .sub("</body>", '<applet code="https://attacker.invalid/a.class"></applet></body>')

    Tempfile.create(["higgs-hostile-final", ".html"]) do |file|
      file.write(hostile)
      file.flush
      validator = File.expand_path("../scripts/validate_higgs_data.rb", __dir__)
      stdout, stderr, status = Open3.capture3(RbConfig.ruby, validator, file.path)
      refute status.success?
      assert_match(/unsafe final element (?:style|applet)/, stdout + stderr)
    end
  end

  def test_public_output_path_is_direct_html_only
    site_root = "/tmp/example/higgs-data"
    assert HiggsHtmlSafety.public_html_output?("#{site_root}/index.html", site_root)
    refute HiggsHtmlSafety.public_html_output?("#{site_root}/_data/analysis.json", site_root)
    refute HiggsHtmlSafety.public_html_output?("#{site_root}/media/poster.html", site_root)
    refute HiggsHtmlSafety.public_html_output?("#{site_root}/higgs-data.js", site_root)
  end
end
