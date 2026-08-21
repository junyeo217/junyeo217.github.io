module HiggsHtmlSafety
  FORBIDDEN_FRAGMENT_ELEMENTS = %w[
    animate animatemotion animatetransform base embed foreignobject form iframe link meta object script set style
  ].freeze
  EXECUTABLE_URL_ATTRIBUTES = %w[action formaction href poster src xlink:href].freeze
  ASCII_URL_CONTROL = /[\u0000-\u001F\u007F]/.freeze
  EXECUTABLE_URL_SCHEME = /\A(?:javascript|vbscript|data:text\/html)/i.freeze
  UNSAFE_INLINE_STYLE = /(?:expression\s*\(|javascript\s*:|url\s*\()/i.freeze

  module_function

  def local_media_url?(value)
    value.to_s.match?(%r{\A/higgs-data/media/[A-Za-z0-9][A-Za-z0-9._-]*\z})
  end

  def fragment_element_error(name)
    normalized_name = name.to_s.downcase
    return "unsafe element #{normalized_name}" if FORBIDDEN_FRAGMENT_ELEMENTS.include?(normalized_name)

    nil
  end

  def resource_attribute_error(element_name, name, value)
    normalized_element = element_name.to_s.downcase
    normalized_name = name.to_s.downcase
    raw_value = value.to_s.strip

    return "resource background attribute" if normalized_name == "background"
    if normalized_name == "src" && normalized_element != "script"
      return nil if local_media_url?(raw_value)

      return "non-local resource URL"
    end
    if normalized_name == "poster"
      return nil if local_media_url?(raw_value)

      return "non-local resource URL"
    end
    if %w[href xlink:href].include?(normalized_name) && !%w[a area link].include?(normalized_element)
      return nil if raw_value.start_with?("#") || local_media_url?(raw_value)

      return "non-local resource URL"
    end

    nil
  end

  def attribute_error(element_name, name, value)
    normalized_name = name.to_s.downcase
    return "event attribute #{normalized_name}" if normalized_name.start_with?("on")
    return "srcdoc attribute" if normalized_name == "srcdoc"

    url_error = url_attribute_error(normalized_name, value)
    return url_error if url_error
    return "unsafe inline style" if normalized_name == "style" && value.to_s.match?(UNSAFE_INLINE_STYLE)

    resource_error = resource_attribute_error(element_name, normalized_name, value)
    return resource_error if resource_error

    nil
  end

  def url_attribute_error(name, value)
    normalized_name = name.to_s.downcase
    return "srcset attribute" if normalized_name == "srcset"
    return nil unless EXECUTABLE_URL_ATTRIBUTES.include?(normalized_name)

    raw_value = value.to_s
    return "executable URL" if raw_value.match?(ASCII_URL_CONTROL)

    canonical_value = raw_value.strip
    return "executable URL" if canonical_value.match?(EXECUTABLE_URL_SCHEME)

    nil
  end
end
