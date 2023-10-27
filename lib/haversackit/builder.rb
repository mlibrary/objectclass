require 'pp'
require 'nokogiri'
require 'haversackit/bag'
require 'fileutils'
require 'yaml'

require 'mime/types'
require 'mets'

require 'json'

PARSE_OPTIONS = Nokogiri::XML::ParseOptions::DEFAULT_XML | Nokogiri::XML::ParseOptions::NOBLANKS

module HaversackIt

  class Assigner
    def initialize
      @idcache = Hash.new(0)
    end

    def next_id(prefix='')
      @idcache[prefix] += 1
      "#{prefix}%03d" % @idcache[prefix]
    end
  end

  class Builder
    attr_reader :input_pathname
    attr_reader :sources
    attr_reader :objid, :identifier

    def initialize(input_pathname:, output_pathname:)
      @input_pathname = input_pathname
      @output_pathname = output_pathname
      @objid = @identifier = File.basename(@input_pathname)
      @assigner = Assigner.new
      @sources = {}
      @manifest = []
      @fileidcache = {}
      Dir.glob("#{input_pathname}/**/*.yaml").each do |filename|
        key = File.basename(filename, '.yaml')
        @sources[key.to_sym] = {
          filename: filename,
          stat: File.stat(filename),
          data: YAML.load(File.read(filename))
        }
      end
    end

    def build!
      bag_pathname = "#{@output_pathname}/#{@identifier}"
      if Dir.exists?(bag_pathname)
        FileUtils.rm_rf(bag_pathname)
      end
      bag = HaversackIt::Bag.new bag_pathname

      physical_structmap = @sources.select{ |key, value| key.to_s.start_with?('structmap_physical') }
      objects = []
      queue = [ physical_structmap[:structmap_physical][:data] ].flatten
      while item = queue.shift
        objects << item if item["id"]
        if item["items"]
          item["items"].reverse.each do |item_|
            # objects << item_
            queue.unshift item_
          end
        end
      end

      # objects.each do |object|
      #   pp ID: object['id'], TYPE: object['type']
      # end
      # exit

      objects.each do |item|
        STDERR.puts "-- #{item['id']}"
        bag.add_file("#{item['id']}.mets.xml") do |io|
          io.puts to_xml(item)
        end
      end

      @manifest.each do |file|
        if file.is_a?(Array)
          # STDERR.puts "-- output: #{file[0]}"
          bag.add_file(File.join(file[0])) do |io|
            io.puts file[1]
          end
        end
      end

      FileUtils.cd(@input_pathname) do
        Dir.glob("files/**/*.*").each do |input_filename|
          # filename = input_filename.sub(builder.input_pathname, '')
          # filename = filename[1..-1] if filename[0] == '/'
          STDERR.puts "#{input_filename} :: #{File.symlink?(input_filename) ? '*' : ':'}"
          output_filename = input_filename.gsub("files/", "")
          if File.symlink?(input_filename)
            true_filename = File.readlink(input_filename)
            bag.add_symlink(output_filename, true_filename)
            # bag.add_symlink(File.join(@identifier, input_filename), true_filename)
          else
            bag.add_file(output_filename, input_filename)
          end
        end
      end

      bag.manifest!
    end

    def build_metadata

      build_header
      build_common_dmdsec
      build_links_dmdsec
      build_metadata_dmdsec

      build_amdsec_techmd
      build_amdsec_rightsmd
      build_amdsec_sourcemd
      build_amdsec_digiprovmd
      build_amdsec

      build_filesec

      build_structmap


      # behavior


    end

    def build_header

      source = @sources[:common]

      header = METS::Header.new(
        createdate: format_time(source[:stat].ctime),
        lastmoddate: format_time(source[:stat].mtime),
        recordstatus: "BAGGED"
      )

      # who ran this should be recorded somewhere
      if @sources[:processing]
        if username = @sources[:processing][:data]['username']
          header.add_agent role: "CUSTODIAN", type: "INDIVIDUAL", name: username
        end
      end

      header.add_agent role: "CUSTODIAN", type: "ORGANIZATION", name: "DLPS"
      # header.add_alt_record_id 'ia.londonspybookoft00burk', type: 'IAidentifier'
      @mets.header = header

    end

    def build_common_dmdsec
      source = @sources[:common]

      data = source[:data].dup
      if data['.nested'][@objid]
        data['.nested'][@objid].keys.each do |key|
          data[key] = data['.nested'][@objid][key]
        end
      end

      builder = Nokogiri::XML::Builder.new do |xml|
        xml.root('xmlns:dcterms' => 'http://purl.org/dc/terms/') {
          data.keys.each do |key|
            next if key == '.nested'
            tag = key.split(":")[-1]
            if data[key]
              values = [ data[key] ].flatten
              values.each do |value|
                xml['dcterms'].send(tag, value)
              end
            end
          end
        }
      end

      nodes = builder.doc.root.element_children
      dmd_sec = METS::MetadataSection.new 'dmdSec', id: 'DMDCOMMON'
      dmd_sec.set_xml_node(nodes, mdtype: 'DC', label: 'Common Metadata')
      @mets.add_dmd_sec(dmd_sec)
    end

    def build_links_dmdsec
      if @objid == @identifier
        source = @sources[:links]
        return unless source
      else
        source = { data: {} }
        source[:data]["isPartOf"] = []
        source[:data]["isPartOf"] << { 'href' => "urn:quombat:objects:#{@identifier}", 'title' => @sources[:common][:data]["dc:title"] }
      end

      data = source[:data]
      if data.keys & [ 'memberOf', 'isPartOf', 'up', 'prev', 'next' ]
        builder = Nokogiri::XML::Builder.new do |xml|
          xml.root('xmlns:dcterms' => 'http://purl.org/dc/terms/', 'xmlns:dcam' => 'http://purl.org/dc/dcam/') {
            if data['memberOf']
              data["memberOf"].each do |item|
                xml['dcam'].memberOf 'xlink:href': item['href'], 'xlink:title': item['title']
              end
            end

            [ "up", "prev", "next" ].each do |link|
              next unless data[link]
              # STDERR.puts "=== #{link}"
              datum = data[link]
              xml['dcterms'].relation 'xlink:href': datum['href'], 'xlink:title': datum['title'], 'xlink:role': "dlxs:#{link}"
            end

            if data['isPartOf']
              data["isPartOf"].each do |item|
                xml['dcterms'].isPartOf 'xlink:href': item['href'], 'xlink:title': item['title']
              end
            end
          }
        end
        nodes = builder.doc.root.element_children
        dmd_sec = METS::MetadataSection.new 'dmdSec', id: 'DMDRELATED'
        dmd_sec.set_xml_node(nodes, mdtype: 'DC', label: 'Related Objects')
        @mets.add_dmd_sec(dmd_sec)
      end
    end

    def build_metadata_dmdsec
      # sources = @sources.keys.grep(/metadata/)
      if @objid == @identifier
        sources = [ 'metadata' ]
      else
        key = "metadata_#{@objid}"
        sources = @sources.keys.grep(/#{key}/)
      end
      return if sources.empty?

      links = @sources[:links][:data]
      schema = nil
      links['memberOf'].each do |link|
        if link['href'].index(':collection:')
          schema = link['href'].gsub('collection', 'schema')
        end
      end
      if schema.nil?
        schema = 'urn:x-umich:schema:default'
      end

      sources.each do |source|

        next unless @sources[source]
        data = @sources[source][:data]

        dmd_id = generate_id('DMD', data['@id'])

        dmd_sec = METS::MetadataSection.new 'dmdSec', id: dmd_id

        params = {}
        # this should probably be xlink:href
        if data['href']
          params[:xlink] = { href: data['href'] }
          if data['xptr'] then
            params[:xptr] = "xpointer(#{data['xptr']})"
          end
          params[:mdtype] = 'TEIHDR';
          params[:label] = 'Work Metadata'
          params[:loctype] = 'URL'
        elsif data['mimetype'] and data['mimetype'] == 'text/dlxs+x-yaml'
          # output as JSON
          builder = {}
          builder['@schema'] = schema
          data.keys.each do |key|
            next if key.start_with?('@')
            next if key == 'mimetype' # useless
            builder[key] = data[key]
          end
          metadata_filename = "files/#{data['@id'] || @objid}.metadata.json"
          # then builder is written to this file
          @manifest << [ metadata_filename, JSON.pretty_generate(builder) ]

          params[:xlink] = { href: metadata_filename }
          params[:mdtype] = 'OTHER';
          params[:othermdtype] = 'DLXS ImageClass Metadata'
          params[:mimetype] = 'application/json'
          params[:label] = data['@label'] || 'Work Metadata'
          params[:loctype] = 'URL'

        else
          builder = Nokogiri::XML::Builder.new do |xml|
            xml.record('xmlns' => 'http://lib.umich.edu/dlxs/metadata') {
              data.keys.each do |key|
                next if key.start_with?('@')
                next if key == 'mimetype' # useless
                xml.field(abbrev: key) {
                  values = [ data[key] ].flatten
                  values.each do |value|
                    xml.value value
                  end
                }
              end
            }
          end

          metadata_filename = "files/#{data['@id'] || @objid}.metadata.xml"
          # then builder is written to this file
          @manifest << [ metadata_filename, builder.to_xml ]

          params[:xlink] = { href: metadata_filename }
          params[:mdtype] = 'OTHER';
          params[:othermdtype] = 'DLXS ImageClass XML'
          params[:label] = data['@label'] || 'Work Metadata'
          params[:loctype] = 'URL'
        end
        dmd_sec.set_md_ref(**params)
        @mets.add_dmd_sec(dmd_sec)

      end
    end

    def build_amdsec
      unless @amdsecs.empty?
        @mets.add_amd_sec(next_id('AMD'), *@amdsecs)
      end
    end

    def build_amdsec_techmd
    end

    def build_amdsec_rightsmd
    end

    def build_amdsec_sourcemd
      return unless @objid == @identifier
      return unless ( source = @sources[:source] ? @sources[:source][:data] : nil )
      amd_sec = METS::MetadataSection.new 'sourceMD', id: next_id('AMD')
      params = build_mdref(source)
      amd_sec.set_md_ref(**params)
      @amdsecs << amd_sec
    end

    def build_amdsec_digiprovmd
    end

    def build_filesec
      return unless ( filesets = @sources[:filesets] ? @sources[:filesets][:data] : nil )
      possible_filesets = [ @item['href'][1..-1] ]
      filesets.each do |fileset|
        next unless possible_filesets.index(fileset["id"])
        attrs = {}
        attrs[:use] = fileset["use"] if fileset["use"]
        attrs[:id] = fileset["id"] || next_id('FG')
        attrs[:assigner] = @assigner
        filegroup = METS::FileGroup.new **attrs
        fileset["files"].each_with_index do |file, seq|
          @fileidcache[[file['href']]] = file['id'] || next_id('FID')
          href = file['href'].dup
          if href.is_a?(Array)
            # href[0] = "bag://#{@identifier}/data/#{@identifier}/#{href[0]}"
            href[0] = "urn:quombat:#{@identifier}:file:#{href[0]}"
            href = href.join('')
          end
          filegroup.add_file(
            href,
            # seq: file['seq'],
            seq: false,
            path: File.join(@input_pathname),
            mimetype: file['mimetype'],
            use: file['use'],
            id: @fileidcache[[file['href']]],
          )
        end
        @mets.add_filegroup(filegroup)
      end
    end

    def build_structmap
      structmaps = @sources.select{ |key, value| key.to_s.start_with?('structmap_') }

      structmaps.each do |filename, value|
        type = filename.to_s.sub('structmap_', '')

        structmap = METS::StructMap.new type: type

        if type == 'physical'
          if @objid == @identifier
            build_structmap_physical_object(structmap, value[:data], order: false)
          else
            build_structmap_physical_nested(structmap, value[:data], order: false)
          end
        elsif @objid == @identifier
          build_structmap_div(structmap, value[:data], order: false)
        end

        @mets.add_struct_map(structmap) unless structmap.empty?
      end
    end

    def build_structmap_physical_object(parent, items, order: true)
      items.each_with_index do |item, seq|
        params = { type: item['type'], orderlabel: item['orderlabel'], label: [item['label']].flatten.join(' / ')}
        if order then
          params[:order] = item['seq'] || (seq + 1)
        end
        if item['idref']
          params[:dmdid] = item['idref'].map{|idref| "DMD.#{idref.gsub(':', '.')}" }.join(' ')
        end
        div = METS::StructMap::Div.new(**params)
        parent.add_div(div)
        if item["items"]
          build_structmap_div_links(div, item["items"])
        end
      end
    end

    def build_structmap_div_links(parent, items, order: true)
      items.each_with_index do |item, seq|
        params = { type: item['type'], orderlabel: item['orderlabel'], label: [item['label']].flatten.join(' / ')}
        if order then
          params[:order] = item['seq'] || (seq + 1)
        end
        div = METS::StructMap::Div.new(**params)
        if item['files']
          item['files'].each do |file|
            hrefs = [ file['href'] ].flatten
            fileid = @fileidcache[hrefs] || hrefs
            div.add_fptr(fileid: fileid, xptr: file['xptr'])
          end
        end
        if item['href'] then
          fileid = item['id']
          div.add_mptr(href: "bag://#{@identifier}/data/#{fileid}", loctype: 'URL')
        end
        parent.add_div(div)
        if item['items'] then
          build_structmap_div_links(div, item['items'])
        end
      end
    end

    def build_structmap_physical_nested(parent, items, order: true)
      # find the item from the main structmap
      item = items[0]["items"].select{|i| i["id"] == @objid }.first
      build_structmap_div(parent, [item], order: order)
    end

    def build_structmap_div(parent, items, order: true)
      items.each_with_index do |item, seq|
        next if item.nil?
        # pp AHOY: 'div', ITEM: item
        params = { type: item['type'], orderlabel: item['orderlabel'], label: [item['label']].flatten.join(' / ')}
        if order then
          params[:order] = item['seq'] || (seq + 1)
        end
        if item['idref']
          params[:dmdid] = item['idref'].map{|idref| "DMD.#{idref.gsub(':', '.')}" }.join(' ')
        end
        div = METS::StructMap::Div.new(**params)

        if item['files'] then
          item['files'].each do |file|
            hrefs = [ file['href'] ].flatten
            if file['href'].nil?
              PP.pp item, STDERR
            end
            if hrefs[0].start_with?('urn:') then
              div.add_mptr(href: hrefs[0], loctype: 'URN')
            else
              PP.pp file, STDERR
              fileid = @fileidcache[hrefs] || hrefs[0]
              div.add_fptr(fileid: fileid, xptr: file['xptr'])
            end
          end
        elsif item['href'] then
          fileid = item['href']
          div.add_mptr(href: fileid, loctype: 'URL')
        end

        parent.add_div(div)

        if item['items'] then
          # pp AHOY: 'nested', ITEM: item
          build_structmap_div(div, item['items'])
        end
      end
    end

    def build_structmap_sequence(data)
      struct_map = METS::StructMap.new
      div = METS::StructMap::Div.new(type: 'sequence')
      struct_map.add_div(div)
      data.each_with_index do |datum, i|
        if datum.has_key?('mptr')
          div2 = div.add_mptr_div(
            [ datum['mptr'] ],
            order: i + 1,
            type: datum['type'],
            label: datum['label']
          )
        else
          div2 = div.add_file_div(
            fileptrs,
            order: i,
            type: type,
            label: label
          )
        end
      end
      struct_map
    end

    def to_xml(item)

      @item = item
      @objid = item["id"]

      @amdsecs = []
      @mets = METS::Document.new objid: @objid

      build_metadata
      @mets.to_node.to_s
    end

    def format_time(time)
      time.gmtime.strftime("%Y-%m-%dT%H:%M:%S")
    end

    def generate_id(prefix='', id=nil)
      if id
        "#{prefix}#{prefix ? '.' : ''}#{id.gsub(':', '.')}"
      else
        next_id(prefix)
      end
    end

    def next_id(prefix='')
      @assigner.next_id(prefix)
    end

    def build_mdref(source)
      href = source['href']
      {
        xlink: { href: href },
        label: source['label'],
        **guess_mdtype(source),
        **guess_loctype(href),
        mimetype: guess_mimetype(href),
      }
    end

    def guess_mdtype(source)
      retval = { mdtype: source['mdtype'], othermdtype: source['othermdtype'] }
      unless retval[:mdtype]
        case source['href']
        when /\.hdr/
          retval[:mdtype] = 'TEIHDR'
        else
          retval[:mdtype] = 'OTHER'
          retval[:othermdtype] = case source['href']
          when /\.xslx|\.csv|\.tsv/
            'SPREADSHEET'
          when /name\.umdl\.umich\.edu|hdl\.handle\.net/
            'DLXS TextClass'
          else
            'DATA'
          end
        end
      end
      retval
    end

    def guess_loctype(href)
      retval = {}
      if href.match(/^urn:/) then
        retval[:loctype] = 'URN'
      elsif href.match(/^xpat:/) then
        retval[:loctype] = 'OTHER'
        retval[:otherloctype] = 'XPAT'
      else
        retval[:loctype] = 'URL'
      end
      retval
    end

    def guess_mimetype(href)
      case href
      when /\.xlsx/
        MIME::Types.type_for('.xlsx').first
      when /\.hdr/
        MIME::Types.type_for('.tei').first
      else
        ext = File.extname(href).split('#')[0]
        MIME::Types.type_for(ext).first
      end
    end

  end
end
