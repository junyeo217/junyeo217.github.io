module HiggsHtmlSafety
  FORBIDDEN_FRAGMENT_ELEMENTS = %w[base embed foreignobject form iframe link meta object script].freeze
  EXECUTABLE_URL_ATTRIBUTES = %w[action formaction href poster src xlink:href].freeze
  ASCII_URL_CONTROL = /[\u0000-\u001F\u007F]/.freeze
  EXECUTABLE_URL_SCHEME = /\A(?:javascript|vbscript|data:text\/html)/i.freeze
  UNSAFE_INLINE_STYLE = /(?:expression\s*\(|javascript\s*:|url\s*\()/i.freeze

  module_function

  def fragment_element_error(name)
    normalized_name = name.to_s.downcase
    return "unsafe element #{normalized_name}" if FORBIDDEN_FRAGMENT_ELEMENTS.include?(normalized_name)

    nil
  end

  def attribute_error(name, value)
    normalized_name = name.to_s.downcase
    return "event attribute #{normalized_name}" if normalized_name.start_with?("on")
    return "srcdoc attribute" if normalized_name == "srcdoc"

    url_error = url_attribute_error(normalized_name, value)
    return url_error if url_error
    return "unsafe inline style" if normalized_name == "style" && value.to_s.match?(UNSAFE_INLINE_STYLE)

    nil
  end

  def url_attribute_error(name, value)
    normalized_name = name.to_s.downcase
    return "srcset attribute" if normalized_name == "srcset"
    return nil unless EXECUTABLE_URL_ATTRIBUTES.include?(normalized_name)

    raw_value = value.to_s
    return "executable URL" if raw_value.match?(ASCII_URL_CONTROL)

    canonical_value = raw_value.delete("\t\n\r").strip
    return "executable URL" if canonical_value.match?(EXECUTABLE_URL_SCHEME)

    nil
  end
end
