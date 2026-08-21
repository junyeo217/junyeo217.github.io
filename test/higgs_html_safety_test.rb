require "minitest/autorun"
require "nokogiri"
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

  def test_rejects_forbidden_fragment_elements
    %w[script iframe object embed form base link meta style foreignObject animate animateMotion animateTransform set].each do |name|
      assert_match(/unsafe element/, HiggsHtmlSafety.fragment_element_error(name))
    end
  end

  def test_allows_non_executable_fragment_markup
    assert_nil HiggsHtmlSafety.fragment_element_error("section")
    assert_nil HiggsHtmlSafety.attribute_error("section", "class", "study-card")
    assert_nil HiggsHtmlSafety.attribute_error("section", "style", "--bar: 42%")
  end
end
