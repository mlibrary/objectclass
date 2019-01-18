require 'nokogiri'
require 'base64'

require 'mets'

module METS
  class MetadataSection
    def initialize(element_name, **attrs)
      @attrs = METS.copy_attributes(attrs, %w{ID GROUPID ADMID CREATED STATUS})
      @element_name = element_name
      @components = []
    end

    def set_md_ref(**attrs)
      METS.check_attr_val attrs[:loctype], METS::ALLOWED_LOCTYPE
      METS.check_attr_val attrs[:mdtype], METS::ALLOWED_MDTYPE

      @mdref = [] unless @mdref
      mdref = METS.create_element(
        "mdRef",
        METS.copy_attributes(attrs, [
          'ID',
          METS::LOCATION, METS::METADATA,
          METS::FILECORE, 'LABEL', 'XPTR'
        ])
      )

      METS.set_xlink(mdref, attrs[:xlink]) unless attrs[:xlink].nil?
      @mdref << mdref
    end

    def set_mdwrap(mdwrap)
      @mdwrap = mdwrap
    end

    def set_data(data, **attrs)
      METS.check_attr_val(attrs[:mdtype], METS::ALLOWED_MDTYPE)

      @mdwrap = METS.create_element(
        "mdWrap",
        METS.copy_attributes(attrs, [ 'ID', METS::METADATA, METS::FILECORE, 'LABEL' ])
      )

      if data.is_a?(Nokogiri::XML::Node)
        xml_data_node = METS.create_element('xmlData')
        @mdwrap << xml_data_node
        xml_data_node << data
      elsif data.is_a?(Nokogiri::XML::NodeSet)
        xml_data_node = METS.create_element('xmlData')
        @mdwrap << xml_data_node
        data.each do |datum|
          xml_data_node << datum
        end
      else
        encoded_data = Base64.encode64(data)
        bin_data_node = METS.create_element("binData", nil, encoded_data)
        @mdwrap << bin_data_node
      end
    end

    def set_xml_file(xmlfile, **kwargs)
      parsed_xml = ::File.open(xmlfile) { |f| Nokogiri::XML(f) }
      set_xml_node(parsed_xml.root, **kwargs)
    end

    def set_xml_node(node, **kwargs)
      set_data(node, mimetype: "text/xml", **kwargs)
    end

    def add_md_sec(section, **kwargs)
      if section.is_a?(String)
        element_name = section
        section = METS::MetadataSection.new(element_name, id: kwargs.delete(:id))
        section.set_md_ref(**kwargs)
      end
      @components << section
    end

    def to_node
      node = METS.create_element(@element_name, @attrs)
      if @mdref
        @mdref.each do |mdref|
          node << mdref
        end
      end
      # node << @mdref if @mdref
      node << @mdwrap if @mdwrap
      unless @components.empty?
        @components.each do |section|
          node << METS.object_or_node_to_node(section)
        end
      end
      node
    end

  end
end

