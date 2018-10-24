require 'haversackit/haversack'

require 'net/http'

module HaversackIt
  class Haversack::TextClass < Haversack
    def initialize(collid:, idno:, parts:)
      @collid = collid
      @idno = idno.downcase
      @parts = parts

      @SKIP_LABELS = ["", "UNSPEC", "UNS"]
      @div_labels = {}
      @div_types = {}

      if @parts.empty?
        @parts = { 1 => 'Title', 2 => 'Volume' }
      end

      super
    end

    def build_common
      header = @text.xpath('./HEADER').first
      identifier = header.at_xpath('.//IDNO[@TYPE="dlps"]').content.downcase
      encoding_type = @text.at_xpath('//DocEncodingType[1]').content
      @common = {}
      @common['dc:type'] = @xmldoc.at_xpath('//DlxsGlobals/EncodingType').content
      @common['dc:conformsTo'] = "http://www.tei-c.org/SIG/Libraries/teiinlibraries/main-driver.html#level-#{@encoding_level}-content"
      @common['dc:identifier'] = identifier
      @common['dc:title'] = header.at_xpath('.//FILEDESC/TITLESTMT/TITLE[@TYPE="245"]').content.strip
      @common['dc:creator'] = header.xpath('string(.//FILEDESC/TITLESTMT/AUTHOR)').strip #.content
      @common.delete('dc:creator') if @common['dc:creator'].empty?

      # there's no dc:description
      @common['dc:subject'] = []
      header.xpath('.//PROFILEDESC/TEXTCLASS/KEYWORDS/TERM').each do |term|
        @common['dc:subject'] << term.content
      end
    end

    def build_metadata
      @metadata['href'] = "files/#{@idno}.xml"
      @metadata['xptr'] = "//HEADER"
    end

    def build_rights
      @rights['mimetype'] = "application/tei+xml"
      @rights['href'] = "files/#{@idno}.xml"
      @rights['xptr'] = "//HEADER/FILEDESC/PUBLICATIONSTMT/AVAILABILITY"
    end

    def build_source
      @source['mimetype'] = "application/tei+xml"
      @source['href'] = "files/#{@idno}.xml"
    end

    def build_links
      @links['memberOf'] = []
      # @links['memberOf'] = ["urn:x-umich:collection:#{@collid}"]
      @db[:nameresolver].where(id: @idno).each do |row|
        colldata = @db[:Collection].where(userid: 'dlxsadm', collid: row[:coll]).first
        @links['memberOf'] << {
          "href" => "urn:x-umich:collection:#{row[:coll]}",
          "title" => colldata[:collname]
        }
        # if row[:coll] != @collid
        #   @links['memberOf'] << "urn:x-umich:collection:#{row[:coll]}"
        # end
      end
      build_links_ispartof
    end

    def build_links_ispartof
      @links['isPartOf'] = []
      parts = @idno.split(".")
      parts.pop # this volume

      tmp = []
      parts.each do |part|
        tmp << part
        didno = tmp.join('.')

        data = {"label" => "#{@parts[tmp.length]}", "items" => []}

        fetch_data_url = "https://#{DLXS_SERVICE}/cgi/t/text/text-idx?cc=#{@collid};idno=#{didno};debug=xml"
        fetch_data_uri = URI(fetch_data_url)
        response = Net::HTTP.get_response(fetch_data_uri)
        doc = Nokogiri::XML(response.body)
        doc.xpath("//Picklist/Item").each do |item|
          idno = item.xpath("string(./ItemHeader/HEADER//IDNO[@TYPE='dlps'])")
          title = item.xpath("string(./ItemHeader/HEADER/FILEDESC/TITLESTMT/TITLE)").gsub(/\s+/, ' ')
          data["items"] << {
            "title" => title,
            "href"  => "urn:x-umich:work:#{idno}"
          }
        end

        if data["items"].length > 1
          @links['isPartOf'] << data
        end

      end
    end

    def build_filegroups
      @filegroups['encoded_text'] = []
      @filegroups['bitonal'] = []
      @filegroups['contone'] = []

      # there's only one of these
      @filegroups['encoded_text'] << {
        # "href" => "files/#{@idno}.xml\#xpointer(/DLPSTEXTCLASS/TEXT)",
        "href" => "files/#{@idno}.xml",
        "loctype" => "URL",
        "mimetype" => "application/tei+xml",
        "files" => []
      }

      # get bitonal/contone from the database
      @db[:Pageview].where(idno: @idno).order(:seq).each do |row|
        group = row[:bpp] == 1 ? 'bitonal' : 'contone'
        seq = row[:seq]
        @files[seq] = [] if @files[seq].nil?
        @filegroups[group] << {
          "href" => "files/#{row[:image]}",
          "seq"  => seq,
          "loctype" => "URL"
        }
        @files[seq] << @filegroups[group][-1]["href"]
        @manifest << Pathname.new(@identifier_pathname.join(row[:image]))
      end

      pb_node_track = {}
      @text.xpath('./TEXT/BODY/DIV1').each do |div1_node|
        node_id = div1_node['NODE']
        div1_node.xpath('P').each do |p_node|
          pb_node = p_node.at_xpath('PB')
          seq = pb_node['SEQ']

          ## href = %Q{#xpointer(/DLPSTEXTCLASS/TEXT/BODY/DIV[@NODE="#{node_id}"]/P[PB[@SEQ=\"#{pb_node['SEQ']}\"]])}
          ## -- shortening after conversations with sooty
          href = %Q{#xpointer(/DLPSTEXTCLASS/TEXT/BODY/DIV1//P[PB[@SEQ=\"#{pb_node['SEQ']}\"]][1])}

          @files[seq] = [] if @files[seq].nil?
          next if @files[seq] and @files[seq].index(href)
          next if pb_node_track[seq]

          @files[seq] << href
          pb_node_track[seq] = true
          @filegroups['encoded_text'][-1]['files'] << {
            "href" => href,
            "loctype" => "URL",
            "seq" => seq,
          }
          # href = "files/#{pb_node['REF']}"
          # @manifest << Pathname.new(@identifier_pathname.join(pb_node['REF']))
          # @files[seq] << href
          # @filegroups['bitonal'] << {
          #   "href" => href
          # }
          # contone = @db[:Pageview].where(idno: @idno, bpp: 8, seq: seq).first
          # if contone
          #   href = "files/#{contone[:image]}"
          #   @manifest << Pathname.new(@identifier_pathname.join(contone[:image]))
          #   @filegroups['contone'] << {
          #     "href" => href
          #   }
          #   @files[seq] << href
          # end
        end
      end
    end

    def build_structmaps
      @structmaps['physical'] = []
      @structmaps['logical'] = []

      ## this is actually the logical structmap
      @structmaps['physical'] << {"id" => @idno, "label" => @common["dc:title"], "type" => @common["dc:format"], "items" => []}

      @files.keys.each do |seq|
        @structmaps['physical'][-1]['items'] << {
          "type" => "page",
          "seq"  => seq,
          "files" => @files[seq].map{|v| { "href" => v }}
        }
      end

      tracked_files = {}
      @text.xpath('./TEXT/BODY/DIV1').each do |div1_node|
        node_id = div1_node['NODE']

        if @encoding_level == '2'
          div = {"id" => node_id, "label" => @div_labels[node_id], "type" => (@div_types[node_id] || 'section'), "items" => []}
          @structmaps['logical'] << div
        end

        div1_node.xpath('P').each do |p_node|
          pb_node = p_node.at_xpath('PB')
          # @structmaps['physical'][-1]['items'] << make_page(pb_node) unless tracked_files[pb_node['SEQ']]
          div["items"] << make_page(pb_node) if @encoding_level == '2'
          # tracked_files[pb_node['SEQ']] = true
          update_structmap_physical_div(pb_node)
        end
      end
    end

    def setup_identifier_pathname
      STDERR.puts "-- #{@idno} -- "
      Pathname.new(File.join(
              "/quod/obj",
              @idno[0],
              @idno[1],
              @idno[2],
              @idno
            ))
    end

    def fetch_data
      fetch_uri = URI("https://#{DLXS_SERVICE}/cgi/t/text/text-idx?cc=#{@collid};idno=#{@idno};rgn=main;view=text;debug=xml")
      response = Net::HTTP.get_response(fetch_uri)
      ## this is not sufficient because DLXS does not return a correct status code on error
      unless response.is_a?(Net::HTTPSuccess)
        STDERR.puts "FAILED: #{response.code}"
        PP.pp response, STDERR
        exit
      end
      @xmldoc = Nokogiri::XML(response.body)
      @text = @xmldoc.xpath('//DLPSTEXTCLASS').first
      @encoding_level = @text.xpath('string(./HEADER//EDITORIALDECL/@N)')
      if @encoding_level == '2'
        fetch_toc_data
      end
      @manifest << [ "#{@idno}.xml",  @text.to_xml ]
    end

    def fetch_toc_data
      fetch_data_url = "https://#{DLXS_SERVICE}/cgi/t/text/text-idx?cc=#{@collid};idno=#{@idno};view=toc;debug=xml"
      fetch_data_uri = URI(fetch_data_url)
      response = Net::HTTP.get_response(fetch_data_uri)
      @tocdoc = Nokogiri::XML(response.body)
      @tocdoc.xpath("//HeaderToc/DIV1").each do |div1_node|
        ## grab TYPE as well
        node_id = div1_node['NODE']
        @div_types[node_id] = div1_node['TYPE']
        if bibl_node = div1_node.at_xpath('Divhead/BIBL')
          node_author = bibl_node.xpath('string(AUTHORIND)')
          node_title = bibl_node.xpath('string(TITLE)')
          node_vol = bibl_node.xpath('string(BIBLSCOPE[@TYPE="vol"])')
          node_iss = bibl_node.xpath('string(BIBLSCOPE[@TYPE="iss"])')
          node_mo = bibl_node.xpath('string(BIBLSCOPE[@TYPE="mo"])')
          node_year = bibl_node.xpath('string(BIBLSCOPE[@TYPE="year"])')
          node_pg= bibl_node.xpath('string(BIBLSCOPE[@TYPE="pg"])')
          label = node_title
          label += ", #{node_author}" unless node_author.empty?
          extra = []
          extra <<  node_year unless node_year.empty?
          extra << "Vol. #{node_vol}" unless node_vol.empty?
          extra << "Issue #{node_vol}" unless node_iss.empty?
          extra << "Pp. #{node_pg}" unless node_pg.empty?
          unless extra.empty?
            label += " (#{extra.join('; ')})"
          end
          @div_labels[node_id] = label
        elsif head_node = div1_node.at_xpath('Divhead/HEAD')
          @div_labels[node_id] = head_node.content
        end
      end
    end

    def make_page(pb_node)
      seq = pb_node['SEQ']
      page = {"type" => "page", "seq" => seq}
      unless pb_node['N'].nil? or pb_node['N'].empty?
        page["orderlabel"] = pb_node['N']
      end
      if @SKIP_LABELS.index(pb_node['FTR']).nil? then
        page['label'] = pb_node['FTR']
      end
      page["files"] = []
      @files[seq].each do |href|
        page["files"] << { "href" => href }
      end
      page
    end

    def update_structmap_physical_div(pb_node)
      seq = pb_node['SEQ']
      page = @structmaps['physical'][-1]["items"].select{|item| item["seq"] == seq}.first
      return if page.nil?
      unless pb_node['N'].nil? or pb_node['N'].empty?
        page["orderlabel"] = pb_node['N']
      end
      if @SKIP_LABELS.index(pb_node['FTR']).nil? then
        page['label'] = pb_node['FTR']
      end
    end

  end
end
