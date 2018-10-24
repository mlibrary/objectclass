require 'nokogiri'

require 'mets'

module METS
  class StructMap
    def initialize(**attrs)
      @attrs = METS.copy_attributes(attrs, %w{ID TYPE LABEL ADMID DMDID})
      @xmlns = attrs.select{|key, value| key.to_s.index('xmlns:') }
      @components = []
    end

    def add_file_div(fileids, **attrs)
      div = METS::StructMap::Div.new(**attrs)
      fileids.each do |fileid|
        div.add_fptr(fileid: fileid)
      end
      add_div(div)
    end

    def add_mptr_div(fileids, **attrs)
      div = METS::StructMap::Div.new(**attrs)
      fileids.each do |fileid|
        STDERR.puts fileid
        div.add_mptr(href: fileid)
      end
      add_div(div)
    end

    def add_div(div)
      @components << div
    end

    def to_node(nodename='structMap')
      node = METS.create_element(nodename, @attrs)
      unless @xmlns.nil? or @xmlns.empty?
        @xmlns.each do |prefix, href|
          node.add_namespace_definition(prefix.to_s[6..-1], href)
        end
      end
      @components.each do |component|
        node << METS.object_or_node_to_node(component)
      end
      node
    end
  end

  class StructMap::Div < StructMap
    def initialize(**attrs)
      @attrs = METS.copy_attributes(attrs, %w{ID ORDER ORDERLABEL LABEL DMDID ADMID TYPE CONTENTIDS})
      @components = []
    end

    def add_fptr(**attrs)
      fptr = METS.create_element('fptr',
        METS.copy_attributes(attrs, %w{ID FILEID CONTENTIDS}))

      @components << fptr
    end

    def add_mptr(**attrs)
      attrs['LOCTYPE'] = 'OTHER'
      attrs['OTHERLOCTYPE'] = 'system'
      mptr = METS.create_element('mptr',
        METS.copy_attributes(attrs, %w{LOCTYPE OTHERLOCTYPE}))

      # and the xlink:href
      METS.set_xlink(mptr, { href: attrs[:href]})

      @components << mptr
    end

    def to_node
      super("div")
    end
  end

end
