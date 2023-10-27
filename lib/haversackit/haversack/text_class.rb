require 'haversackit/haversack'

require 'net/http'

module HaversackIt
  class Haversack::TextClass < Haversack
    def initialize(collid:, idno:, parts:, symlink: true)
      @collid = collid
      @idno = idno.downcase
      @parts = parts
      @symlink = symlink

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

      @common['.nested'] = {}
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

        data = {"label" => "#{@parts[tmp.length]}", "items" => {}}

        next_idno = previous_idno = last_idno = nil

        fetch_data_url = "https://#{DLXS_SERVICE}/cgi/t/text/text-idx?cc=#{@collid};idno=#{didno};debug=xml"
        fetch_data_uri = URI(fetch_data_url)
        response = Net::HTTP.get_response(fetch_data_uri)
        doc = Nokogiri::XML(response.body)
        doc.xpath("//Picklist/Item").each do |item|
          idno = item.xpath("string(./ItemHeader/HEADER//IDNO[@TYPE='dlps'])").downcase
          title = item.xpath("string(./ItemHeader/HEADER/FILEDESC/TITLESTMT/TITLE)").gsub(/\s+/, ' ')
          # data["items"] << {
          #   "title" => title,
          #   "href"  => "urn:x-umich:work:#{idno}"
          # }
          data["items"][idno] = {
            "title" => title,
            "href"  => "urn:x-umich:work:#{idno}"
          }
          STDERR.puts "-- > #{@idno} :: #{idno} :: #{last_idno}"
          if idno == @idno
            previous_idno = last_idno
          elsif last_idno == @idno
            next_idno = idno
          end
          last_idno = idno
        end

        # if data["items"].length > 1
        #   @links['isPartOf'] << data
        # end

        @links["up"] = { "title" => data["label"], "href" => "urn:x-umich:work:#{didno}" }
        @links["prev"] = data["items"][previous_idno] if previous_idno
        @links["next"] = data["items"][next_idno] if next_idno

      end
    end

    def build_filesets
      # add an entry for the full encoded text
      # or should each of these be a file?
      @filesets << {
        "use" => "encoded_text",
        "id"  => "#{@idno}--XML",
        "files" => [
          {
            "href" => "files/#{@idno}.xml",
            "loctype" => "URL",
            "mimetype" => "application/tei+xml",
            "id" => "#{@idno}--#{generate_id}"
          }
        ]
      }
      @files["encoded_text"] = @filesets[-1]

      # get bitonal/contone from the database
      @db[:Pageview].where(idno: @idno).order(:seq).each do |row|
        group = row[:bpp] == 1 ? 'bitonal' : 'contone'
        seq = "%08d" % row[:seq].to_i
        # @files[seq] = [] if @files[seq].nil?
        if @files[seq].nil?
          @filesets << {
            "id"   => "#{@idno}--FILE#{seq}",
            "group" => "BODY",
            "files" => []
          }
          @files[seq] = @filesets[-1]
        end

        @files[seq]["files"] << {
          "use" => group,
          "href" => "files/#{row[:image]}",
          "mimetype" => get_mimetype(row[:image]),
          "loctype" => "URL",
          "id" => "#{@idno}--#{generate_id}"
        }
        @manifest << Pathname.new(@identifier_pathname.join(row[:image]))
      end

      pb_node_track = {}
      @groups = {}

      # what groups are here?
      @text.xpath('./TEXT').first.element_children.each do |child|
        # @groups << child.name unless @groups.index(child.name)
        @groups[child.name] = child
      end

      all_pb_nodes = @text.xpath('./TEXT//PB').to_a

      all_pb_nodes.each do |pb_node|
        seq = "%08d" % pb_node['SEQ'].to_i
        pb_index = all_pb_nodes.index(pb_node)
        next_pb_node = all_pb_nodes[pb_index + 1]
        next_pb_found = false

        # find the matching group
        parent = pb_node.parent
        while @groups.key(parent).nil?
          parent = parent.parent
        end
        group = @groups.key(parent)

        buffer = []

        node = pb_node
        while next_pb_found == false && node = node.next_sibling
          if node.xpath('.//PB').first
            # the next PB is inside this node
            next_pb_found = true
            buffer << crawl_for_pb(node, next_pb_node)
          elsif node == next_pb_node
            next_pb_found = true
          else
            buffer << node.content
          end
        end

        # now find the next sibling of the pb_node parent
        parent = pb_node.parent
        while next_pb_found == false and parent = parent.next_sibling
          parent.children.each do |child|
            if child.name == 'PB' and child == next_pb_node
              next_pb_found = true
              break
            elsif child.xpath(".//PB").first == next_pb_node
              buffer << crawl_for_pb(child, next_pb_node)
              next_pb_found = true
            else
              buffer << child.content
            end
          end
        end

        if @files[seq].nil?
          @filesets << {
            "id"   => "#{@idno}--FILE#{seq}",
            "group" => group,
            "files" => []
          }
          @files[seq] = @filesets[-1]
        end

        @files[seq]["files"] << {
          "use" => "plain_text",
          "href" => "files/#{seq}.txt",
          "mimetype" => "text/plain",
          "loctype" => "URL",
          "id" => "#{@idno}--#{generate_id}"
        }
        @files[seq]["group"] = group
        if @SKIP_LABELS.index(pb_node['FTR']).nil? then
          @files[seq]['label'] = pb_node['FTR']
        end
        unless pb_node['N'].nil? or pb_node['N'].empty?
          @files[seq]["orderlabel"] = pb_node['N']
          # @common['.nested']["#{@idno}--SEQ#{seq}"]["dc:title"] =
          #   "#{@common["dc:title"]} - #{@files[seq]["orderlabel"]}"
        end

        @manifest << [ "#{seq}.txt",  buffer.join("\n") ]
      end

    end

    def build_structmaps
      @structmaps['physical'] = []
      @structmaps['logical'] = []

      @structmaps['physical'] << {
        "id" => @idno,
        "label" => @common["dc:title"],
        "type" => @common["dc:type"],
        "href" => "##{@idno}--XML",
        "items" => []
      }

      @groupmaps = {}
      @groups.keys.each do |group|
        @structmaps['physical'][-1]['items'] << {
          "label" => group,
          "type" => "q:group",
          "items" => []
        }
        @groupmaps[group] = @structmaps['physical'][-1]['items'][-1]
      end

      pp @groupmaps

      @files.keys.select{|num| num.match?(/^\d+/)}.each do |seq|
        group = @files[seq]["group"]
        @groupmaps[group]['items'] << {
          "id"   => "#{@idno}--SEQ#{seq}",
          "type" => "page",
          "seq"  => seq,
          "href" => "##{@idno}--FILE#{seq}",
          "label" => @files[seq]["label"],
          "orderlabel" => @files[seq]["orderlabel"],
        }

        metadata = {}
        metadata["dc:identifier"] = "#{@idno}--SEQ#{seq}"
        orderlabel = @files[seq]["orderlabel"] || "##{seq.to_i}"
        metadata["dc:title"] = "#{@common["dc:title"]} - #{orderlabel}"
        @common['.nested']["#{@idno}--SEQ#{seq}"] = metadata
      end

      tracked_files = {}
      @text.xpath('./TEXT/node()/DIV1').each do |div1_node|
        node_id = div1_node['NODE']
        STDERR.puts "== #{@encoding_level} :: #{node_id}"

        if @encoding_level == '2'
          @structmaps['logical'] << {"type" => "contents", "items" => []} if @structmaps['logical'].empty?
          div = {"id" => node_id, "label" => @div_labels[node_id], "type" => (@div_types[node_id] || 'section'), "items" => []}
          @structmaps['logical'][-1]['items'] << div

          div1_node.xpath('P').each do |p_node|
            pb_node = p_node.xpath('PB').first
            div["items"] << make_page(pb_node) if ( @encoding_level == '2' )
            break
            # update_structmap_physical_div(pb_node)
          end
        end

        if @encoding_level == '4'
          # this structmap is just about the fulltext
          # this might actually be an AREA
          # fptr
          # ...area
          # .....@BETYPE=XPTR
          # .....@BEGIN=//DIV1[@NODE=$NODE]

          @structmaps['logical'] << {"type" => "contents", "items" => []} if @structmaps['logical'].empty?

          # label = nil
          # if false and div1_node.xpath('.//DOCTITLE/TITLEPART').first
          #   label = div1_node.xpath('.//DOCTITLE/TITLEPART').first
          #   label = label.children.first.content unless label.nil?
          # elsif div1_node.xpath('./HEAD').first
          #   label = div1_node.xpath('./HEAD').first
          #   unless label.nil?
          #     tmp = []
          #     label.children.each do |child|
          #       tmp << child.content
          #     end
          #     label = tmp.join(' ')
          #   end
          # end
          # label = ( ! label.nil? ) ? label.children.first.content : div1_node['TYPE']

          label = @div_labels[node_id]
          div = {
            "id" => node_id,
            "label" => label,
            "type" => (div1_node['TYPE'] || 'section'),
            "files" => [
              {
                #{ }"href" => "##{@idno}--XML",
                "href" => @files["encoded_text"]["files"][0]["href"],
                "xptr" => "//DIV1[@NODE=\"#{node_id}\"]",
              }
            ]
          }
          @structmaps['logical'][-1]['items'] << div

        end

      end
    end

    def setup_identifier_pathname
      STDERR.puts "-- #{@idno} -- "
      Pathname.new(File.join(
              ENV['DLXSDATAROOT'],
              'obj',
              @idno[0],
              @idno[1],
              @idno[2],
              @idno
            ))
    end

    def fetch_data
      unless File.exists?("/tmp/#{@idno}.xml")
        fetch_uri = URI("https://#{DLXS_SERVICE}/cgi/t/text/text-idx?cc=#{@collid};idno=#{@idno};rgn=main;view=text;debug=xml")
        response = Net::HTTP.get_response(fetch_uri)
        ## this is not sufficient because DLXS does not return a correct status code on error
        unless response.is_a?(Net::HTTPSuccess)
          STDERR.puts "FAILED: #{response.code}"
          PP.pp response, STDERR
          exit
        end
        File.open("/tmp/#{@idno}.xml", "w") { |f| f.write(response.body) }
      end
      @xmldoc = Nokogiri::XML(File.open("/tmp/#{@idno}.xml").read)
      @text = @xmldoc.xpath('//DLPSTEXTCLASS').first
      @encoding_level = @text.xpath('string(./HEADER//EDITORIALDECL/@N)')
      if @encoding_level == '2' || @encoding_level == '4'
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
          @div_labels[node_id] = label.gsub("\n", ' ').gsub(/\s+/, ' ')
        elsif head_node = div1_node.at_xpath('Divhead/HEAD')
          tmp = []
          head_node.children.each do |child|
            tmp << child.content.gsub("\n", ' ').gsub(/\s+/, ' ')
          end
          @div_labels[node_id] = tmp.join(" ").strip.gsub("\n", ' ').gsub(/\s+/, ' ')
        else
          @div_labels[node_id] = div1_node['TYPE']
        end
      end
    end

    def make_page(pb_node)
      seq = "%08d" % pb_node['SEQ'].to_i
      page = {"type" => "page", "seq" => seq, "href" => "##{@idno}--SEQ#{seq}"}
      unless pb_node['N'].nil? or pb_node['N'].empty?
        page["orderlabel"] = pb_node['N']
      end
      if @SKIP_LABELS.index(pb_node['FTR']).nil? then
        page['label'] = pb_node['FTR']
      end

      # page["files"] = []
      # @files[seq].each do |href|
      #   page["files"] << { "href" => href }
      # end
      page
    end

    def update_structmap_physical_div(pb_node)
      seq = pb_node['SEQ']
      page = @structmaps['physical'][-1]["items"].select{|item| item["seq"] == seq}.first
      return if page.nil?
      unless pb_node['N'].nil? or pb_node['N'].empty?
        page["orderlabel"] = pb_node['N']
        @common['.nested']["#{@idno}--SEQ#{seq}"]["dc:title"] =
          "#{@common["dc:title"]} - #{page["orderlabel"]}"
      end
      if @SKIP_LABELS.index(pb_node['FTR']).nil? then
        page['label'] = pb_node['FTR']
      end
    end

    def get_mimetype(filename)
      ext = filename.split(".")[-1]
      if ext == 'gif'
        return 'image/gif'
      elsif ext == 'tif'
        return 'image/tiff'
      elsif ext == 'jp2'
        return 'image/jp2'
      else
        return 'application/octet-stream'
      end
    end

    def crawl_for_pb(node, target)
      buffer = []
      queue = []
      node.children.reverse.each do |child|
        queue.unshift(child)
      end
      while node_ = queue.shift
        if node_ == target
          break
        elsif node_.xpath('.//PB').first == target
          node_.children.reverse.each do |child|
            queue.unshift(child)
          end
        else
          buffer << node_.content
        end
      end
      return buffer.join("\n")
    end

  end
end
