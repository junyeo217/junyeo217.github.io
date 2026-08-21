module HiggsHtmlSafety
  FORBIDDEN_FRAGMENT_ELEMENTS = %w[
    animate animatemotion animatetransform applet base embed fencedframe foreignobject form frame frameset iframe link meta object portal script set style
  ].freeze
  EXECUTABLE_URL_ATTRIBUTES = %w[action formaction href poster src xlink:href].freeze
  ASCII_URL_CONTROL = /[\u0000-\u001F\u007F]/.freeze
  EXECUTABLE_URL_SCHEME = /\A(?:javascript|vbscript|data:text\/html)/i.freeze
  SAFE_INLINE_STYLE = /\A--hd-chart-value:\s*(?:100|[0-9]{1,2}(?:\.[0-9]{1,3})?)%\z/.freeze
  RESOURCE_IRI_ATTRIBUTES = %w[
    clip-path color-profile cursor fill filter marker marker-end marker-mid marker-start mask stroke
  ].freeze

  module_function

  def local_media_url?(value)
    value.to_s.match?(%r{\A/higgs-data/media/[A-Za-z0-9][A-Za-z0-9._-]*\z})
  end

  def fragment_element_error(name)
    normalized_name = name.to_s.downcase
    return "unsafe element #{normalized_name}" if FORBIDDEN_FRAGMENT_ELEMENTS.include?(normalized_name)

    nil
  end

  def fragment_errors(root)
    ([root] + root.css("*").to_a).each_with_object([]) do |node, errors|
      element_error = fragment_element_error(node.name)
      errors << element_error if element_error

      node.attribute_nodes.each do |attribute|
        attribute_error = attribute_error(node.name, attribute.name, attribute.value)
        errors << attribute_error if attribute_error
      end
    end
  end

  def resource_iri_error(name, value)
    return nil unless RESOURCE_IRI_ATTRIBUTES.include?(name)

    raw_value = value.to_s
    return "external resource IRI" if raw_value.include?("\\") || raw_value.include?("/*")

    canonical_value = raw_value.gsub(/\s+/, "")
    url_count = canonical_value.scan(/url\(/i).length
    return nil if url_count.zero?

    targets = canonical_value.scan(/url\(([^()]*)\)/i).flatten
    return "external resource IRI" unless targets.length == url_count
    return "external resource IRI" unless targets.all? { |target| target.match?(/\A#[A-Za-z_][A-Za-z0-9_.:-]*\z/) }

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
    return "unsupported resource attribute #{normalized_name}" if %w[dynsrc imagesrcset lowsrc ping].include?(normalized_name)

    url_error = url_attribute_error(normalized_name, value)
    return url_error if url_error
    if normalized_name == "style" && !value.to_s.strip.match?(SAFE_INLINE_STYLE)
      return "unsafe inline style"
    end

    iri_error = resource_iri_error(normalized_name, value)
    return iri_error if iri_error

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
