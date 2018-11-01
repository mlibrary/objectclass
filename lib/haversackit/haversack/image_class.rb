require 'haversackit/haversack'

require 'net/http'
require 'dlxs/collection/image_class'

require 'inifile'

def load_constant(name)
  parts = name.split('::')
  klass = Module.const_get(parts.shift)
  klass = klass.const_get(parts.shift) until parts.empty?
  klass
end

module HaversackIt
  class Haversack::ImageClass < Haversack
    def self.create(**argv)
      collid = argv[:collid]
      begin
        require_relative "image_class/#{collid}"
        transform_class = load_constant("HaversackIt::Haversack::ImageClass::#{collid.upcase}")
        STDERR.puts "-- using enhanced #{transform_class}"
      rescue LoadError => e
        STDERR.puts "-- using standard #{transform_class} :: haversackit/haversack/image_class/#{collid}"
        # STDERR.puts e
        transform_class = self
      end
      transform_class.new(**argv)
    end

    def initialize(collid:, m_id:, db:)
       super
       @collid = collid
       @m_id = m_id.downcase
       @idno = "#{@collid}:#{@m_id}"
       # redefine this as an array
       @metadata = []
       @structmaps = Hash.new { |h, k| h[k] = [] }
       @collection = DLXS::Collection::ImageClass.new collid: @collid, db: @db
       @caption_keys = {}
       @not_caption_keys = {}
    end

    def fetch_data

      # figure out what keys are caption keys
      # do we really need to display the filenames for captions??
      admin_map = @collection.admin_map
      admin_map.keys.each do |key|
        next unless key.start_with?('ic_vi')
        admin_map[key].keys.each do |key2|
          @caption_keys[key2.downcase.to_sym] = true
        end
      end

      update_caption_keys

      @record = @db[data_table].where(ic_id: @m_id).first
      @record.delete(:ic_all) # it's useless
      @record.delete(:dlxs_sha)
      @record.keys.each do |key|
        @record[key] = munge(@record[key])
        if key != key.downcase
          @record[key.downcase] = @record.delete(key)
        end
      end

      @record.keys.each do |key|
        if @caption_keys[key]
          @record.delete(key)
        end
      end

      # istruct_stid is important
      @media = media_query.map do |medium|
        medium.keys.grep(/istruct_caption/).each do |key|
          medium[key] = munge(medium[key])
          if key != key.downcase
            medium[key.downcase] = medium.delete(key)
          end
        end
        unless medium.keys.grep(/istruct_caption_/).empty?
          medium.delete(:istruct_caption)
        end
        medium
      end

    end

    def media_query
      query = @db[media_table].
              where(m_id: @m_id).
              order(:istruct_stid, :istruct_face, Sequel.desc(:istruct_stty), Sequel.cast_numeric(:istruct_y), Sequel.cast_numeric(:istruct_x))
      query
    end

    def build_common
      tags = {}
      tags['dc_ti'] = 'dc:title'
      tags['dc_id'] = 'dc:identifier'
      tags['dc_cr'] = 'dc:creator';
      tags['dc_su'] = 'dc:subject';
      tags['dc_pu'] = 'dc:publisher';
      tags['dc_da'] = 'dc:date';
      tags['dc_fo'] = 'dc:format';
      tags['dc_id'] = 'dc:identifier';
      tags['dc_so'] = 'dc:source';
      tags['dc_rel'] = 'dc:relation';
      tags['dc_ri'] = 'dc:rights';
      tags['dc_type'] = 'dc:type';
      tags['dc_la'] = 'dc:language';
      tags['dc_de'] = 'dc:description';
      tags['dc_cov'] = 'dc:coverage';
      tags['dc_ge'] = 'dc:genre';

      @common = Hash.new { |h, k| h[k] = [] }

      ## QUESTION: should this be the system identifier?
      ## or use multiple identifiers?
      @common['dc:identifier'] << "#{@collid}:#{@m_id}"

      tags.keys.each do |tag|
        xcoll_keys = @collection.xcoll_map[tag] || {}

        values = []
        if @record[tag.to_sym] and @record[tag.to_sym].start_with?('"')
          values << @record[tag.to_sym][1..-2]
        elsif @record[tag.to_sym]
          values << @record[tag.to_sym]
        elsif xcoll_keys.keys.length > 0
          xcoll_keys.keys.each do |key|
            if key == '_'
              values << xcoll_keys[key][1..-2]
            else
              values << @record[key.to_sym] unless ( @record[key.to_sym].nil? )
            end
          end
          values.flatten!
        end

        next if values.empty?

        @common[tags[tag]].push(*values) unless values.empty?
      end
    end

    def build_metadata

      admin_map = @collection.admin_map
      # ITEM 1: the record metadata
      metadatum = {}
      metadatum['mimetype'] = "text/dlxs+x-yaml"
      metadatum['@label'] = 'DLXS Record Metadata'
      metadatum['@id'] = "#{@collid}:#{@m_id}"
      @record.keys.each do |key|
        next if @caption_keys[key]
        next if admin_map["ic_fn"] and admin_map["ic_fn"][key.to_s] and @record[key].length > 1
        metadatum[key.to_s] = @record[key] unless blank?(@record[key])
      end
      @metadata << metadatum

      # ITEM 2: the metadata that's unique to captions << which shouldn't be included in ITEM 1
      @orderlabel_keys = []
      if @collid == 'rept2ic'
        @orderlabel_keys << :istruct_caption_captions
      end
      @media.each do |medium|
        possible_keys = medium.keys.grep(/istruct_caption/).select{|key| @orderlabel_keys.index(key).nil? }
        next if possible_keys.empty?
        metadatum = {}
        metadatum['@label'] = "DLXS Image Metadata for #{medium[:m_iid]}"
        metadatum['@id'] = "#{@collid}:#{@m_id}:#{medium[:m_iid]}"
        metadatum['mimetype'] = 'text/dlxs+x-yaml'
        possible_keys.each do |key|
          next if possible_keys.length > 1 and key == :istruct_caption
          next_key = key.to_s.gsub('istruct_caption_', '').gsub('istruct_caption', 'caption')
          next if @not_caption_keys[next_key.to_sym]
          metadatum[next_key] = medium[key] unless blank?(medium[key])
        end
        @metadata << metadatum
      end
    end

    def build_rights
      return unless @common.has_key?("dc:rights") and ! @common["dc:rights"].empty?
      if @common["dc:rights"][0].start_with?('http')
        # is dc:rights a URL?
        @rights['href'] = @common["dc:rights"][0]
      else
        # is dc:rights a text blob?
        @rights['mimetype'] = "text/plain"
        @rights['href'] = "files/#{@idno}.rights.txt"
        @manifest << [ "#{@idno}.rights.txt",  @common["dc:rights"].first ]
      end
    end

    def build_links
      @links['memberOf'] = []
      @links['memberOf'] << {
        "href" => "urn:x-umich:collection:#{@collid}",
        "title" => @collection.config[:collname]
      }

      @db[:GroupColl].where(collids: @collid, userid: @userid)

      query = @db[:GroupColl].where(Sequel.lit("GroupColl.collids = ? AND GroupColl.userid = ?", @collid, @collection.userid)).join(:GroupData, groupid: :groupid, userid: :userid)
      query.each do |group|
        @links['memberOf'] << {
          "href" => "urn:x-umich:group:#{group[:groupid]}",
          "title" => group[:groupname]
        }
      end
    end

    def build_filegroups
      # there are no file groups because the assets
      # are there own objects
    end

    def build_source
    end

    def build_structmaps
      structure_type, possible_structures = parse_structures

      send(:"build_structmaps_#{structure_type}", possible_structures)

    end

    def parse_structures
      possible_structures = Hash.new { |h, k| h[k] = [] }
      possible_stty = {}
      @media.each do |medium|
        key = []
        key << medium[:istruct_stid]
        key << medium[:istruct_face]
        # possible_faces[[medium[:istruct_stid, medium[:istruct_face]]]] << medium
        possible_structures[key] << medium
        possible_stty[medium[:istruct_stty]] = true
      end

      structure_type = "simple"

      bookish_collids = [ 'rept2ic', 'sclib' ]
      if bookish_collids.index(@collid)
        structure_type = "physical"
      elsif possible_stty.keys.length > 1
        structure_type = "structured"
      end
      return structure_type, possible_structures
    end

    def build_structmaps_structured(possible_structures)

      possible_structures.each do |tuple, media|
        stid, face = tuple
        # structure_type = face == 'UNSPEC' ? 'list' : 'structure'
        structure_type = 'structure'

        # what kind of grid are we building?
        num_rows = num_columns = 0

        @structmaps[face.downcase] << {"label" => face, "type" => structure_type, "seq" => stid.to_i, "struct:columns" => 0, "struct:rows" => 0, "items" => []}
        media.each do |medium|
          asset_collid = medium[:m_source] || @collid
          @structmaps[face.downcase][-1]["items"] << {
            "label" => medium[:m_iid],
            "type" => medium[:istruct_stty],
            "struct:x" => medium[:istruct_x].to_i,
            "struct:y" => medium[:istruct_y].to_i,
            "struct:searchable" => ( medium[:m_searchable] == '1' ),
            "idref" => "#{@collid}:#{medium[:m_id]}:#{medium[:m_iid]}",
            "files" => [
              {
                "href" => "urn:umich:x-asset:#{asset_collid}:#{medium[:m_fn]}"
              }
            ]
          }
          num_rows = medium[:istruct_x].to_i if medium[:istruct_x].to_i > num_rows
          num_columns = medium[:istruct_y].to_i if medium[:istruct_y].to_i > num_columns
        end
        @structmaps[face.downcase][-1]["struct:columns"] = num_columns
        @structmaps[face.downcase][-1]["struct:rows"] = num_rows
      end

    end

    def build_structmaps_simple(possible_structures)
      seq = 0
      possible_structures.each do |tuple, media|
        stid, face = tuple
        structure_type = 'list'
        # @structmaps[face.downcase] << {"label" => face, "type" => structure_type, "seq" => stid.to_i, "struct:columns" => 0, "struct:rows" => 0, "items" => []}
        media.each do |medium|
          seq += 1
          asset_collid = medium[:m_source] || @collid
          @structmaps[structure_type] << {
            "label" => medium[:m_iid],
            # "type" => medium[:istruct_stty],
            "struct:x" => medium[:istruct_x].to_i,
            "struct:y" => medium[:istruct_y].to_i,
            "struct:searchable" => ( medium[:m_searchable] == '1' ),
            "seq" => seq,
            "idref" => "#{@collid}:#{medium[:m_id]}:#{medium[:m_iid]}",
            "files" => [
              {
                "href" => "urn:umich:x-asset:#{asset_collid}:#{medium[:m_fn]}"
              }
            ]
          }
        end
      end
    end

    def build_structmaps_physical(possible_structures)
      PP.pp @caption_keys, STDERR
      @structmaps['physical'] << {"id" => @identifier, "label" => @common["dc:title"], "type" => "volume", "items" => []}
      page_type = "page"
      @media.each do |medium|
        asset_collid = medium[:m_source] || @collid
        page = {
          "type" => page_type,
          "seq"  => medium[:istruct_x],
        }
        unless @orderlabel_keys.empty?
          page["label"] = []
          @orderlabel_keys.each do |key|
            page["label"] << medium[key] unless medium[key].nil? or medium[key].empty?
          end
          page["label"] = page["label"].flatten.join(" ")
          page["label"].gsub!(/#{page_type}\s+/i, '')
        end
        page["idref"] = "#{@collid}:#{medium[:m_id]}:#{medium[:m_iid]}" unless medium.keys.grep(/istruct_caption/).select{|key| @orderlabel_keys.index(key).nil? }.empty?
        page["files"] = [
            {
              "href" => "urn:umich:x-asset:#{asset_collid}:#{medium[:m_fn]}"
            }
        ]

        @structmaps['physical'][-1]['items'] << page
      end
    end

    ## utility

    def data_table
      @collection.config[:data_table].to_sym
    end

    def media_table
      @collection.config[:media_table].to_sym
    end

    def blank?(value)
      value.nil? ||
        ( value.respond_to?(:empty?) ? !!value.empty? :
          value.respond_to?(:encoding) ? value.strip.empty? : false )
    end

    def munge(v)
      if v.is_a?(String)
        v.gsub!(/&([^\;]+);/, '__AMP_\1_SEMI__')
        v.gsub!(/\|\|\|; /, '')
        v.gsub!(/<BR>/, '; ')
        v.gsub!(/<br \/>/, '; ')
        v.gsub!(/(\s\;)/, '')
        v.gsub!(/(\;( ){0,1}$)/, '')
        v.gsub!(/^\s*;\s*/, '')
        v.gsub!(/__AMP_([^_]+)_SEMI__/, '&\1;')
        charFilt!(v) # charFilt
        v.gsub!(/\s*$/, '')
        return v.split(/\|\|\||;;;/)
      end
      v
    end

    def reverse_xml_charent_map
      @reverse_xml_charent_map ||= {
        "&lt;" => '<',
        "&gt;" => '>',
        "&apos;" => "'",
        "&quot;" => '"',
        "&amp;" => "&"
      }
    end

    def charFilt!(v)
      # &DlpsUtils::RemapXMLCharentsToChars( \$str );
      v.gsub!(/(\&[a-z]{2,4};)/, reverse_xml_charent_map)
      v.gsub!('&amp;lt;', '__LT__')
      v.gsub!('&amp;gt;', '__GT__')
      v.gsub!(/&amp;([\#a-z0-9A-Z]+);/, '&\1')
      v.gsub!('__LT__', '&lt;')
      v.gsub!('__GT__', '&gt;')
    end

    def update_caption_keys
      # noop
    end

  end

  module Batch
    class ImageClass
      def self.create(collid:, m_id: nil)
        self.new(collid: collid, m_id: m_id)
      end

      def initialize(collid:, m_id: nil)
        @collid = collid
        @identifiers = [m_id].flatten.compact
        config = IniFile.load("#{ENV['DLXSROOT']}/bin/i/image/etc/package.conf")
        @db = Sequel.connect(adapter: 'mysql2', host: 'mysql-quod', user: config['mysql']['user'], password: config['mysql']['password'], database: 'dlxs')
        @collection = DLXS::Collection::ImageClass.new collid: @collid, db: @db
        @haversacks = []
      end

      def build
        gather_identifiers.each do |m_id|
          @haversacks << HaversackIt::Haversack::ImageClass.create(collid: @collid, m_id: m_id, db: @db)
          @haversacks[-1].build
        end
      end

      def save!(base_path)
        @haversacks.each do |haversack|
          haversack.save!(base_path)
        end
      end

      def gather_identifiers
        if @identifiers.empty?
          # gather identifiers, possibly in batch
          # q = @db[@collection.data_table].limit(10).select(:ic_id)
          @db[@collection.data_table].select(:ic_id).limit(10).each do |row|
            @identifiers << row[:ic_id]
          end
        end
        @identifiers
      end

    end

 end
end
