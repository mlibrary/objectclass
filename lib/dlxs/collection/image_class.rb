require 'dlxs/collection'

module DLXS
  class Collection
    class ImageClass < DLXS::Collection

      attr_accessor :xcoll_map, :admin_map, :ic_id

      def load_config

        @config = @db[:Collection].where(Sequel.lit("Collection.collid = ? AND Collection.userid = ?", @collid, @userid)).join(:ImageClass, collid: :collid, userid: :userid)
        @config = @config.first
        @admin_map = _field2map(@config[:field_admin_maps])
        @xcoll_map = _field2map(@config[:field_xcoll_maps])

        ic_id = @admin_map['ic_id'].first[0].downcase

        # find the identifier in the source data
        @ic_id = nil
        @reverse_load_map = {}
        load_map = _field2map(@config[:field_load_maps])
        load_map.keys.each do |key|
          if load_map[key].has_key?(ic_id)
            @ic_id = key
          end
        end
        if @ic_id.nil?
          @ic_id = ic_id
        end
        load_map.keys.each do |key|
          load_map[key].keys.each do |key2|
            @reverse_load_map[key2] = key
          end
        end

        @ic_vi = @admin_map['ic_vi'] || {}
        if not @ic_vi.empty?
          @reverse_ic_vi = {}
          @ic_vi[@admin_map['ic_fn'].first[0].downcase] = 1
        end
        @ic_vi.keys.each do |key|
          key2 = @reverse_load_map[key]
          if @reverse_ic_vi[key2].nil?
            @reverse_ic_vi[key2] = []
          end
          @reverse_ic_vi[key2] << key
        end
        # STDERR.puts "REVERSE_IC_VI = #{@reverse_ic_vi}";
      end

      def data_table
        @config[:data_table].to_sym
      end

      def media_table
        @config[:media_table].to_sym
      end

      private
        def _field2map(s)
          mapping = {}
          if s.nil?
            return mapping
          end
          lines = s.split("|")
          lines.each do |line|
            if not line.empty?
              key, values = line.downcase.split(':::')
              # STDERR.puts "--- #{key} : #{values}"
              mapping[key] = {}
              if values.nil?
                mapping[key][key] = 1
              elsif values[0] == '"'
                mapping[key]['_'] = values
              else
                values.split(' ').each do |value|
                  mapping[key][value.downcase] = 1
                end
              end
            end
          end
          mapping
        end

    end
  end
end
