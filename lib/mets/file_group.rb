require 'nokogiri'

require 'mets'

module METS
  class FileGroup

    attr_reader :components

    def initialize(**attrs)
      @assigner = attrs.delete(:assigner)
      @attrs = METS.copy_attributes(attrs, %w{ID VERSDATE ADMID USE})
      @components = []
      @prefix_counts = Hash.new(0)
      @fileids = {}
      @seq = 0
    end

    def get_file_id(filename)
      id = @fileids[filename]
      id
    end

    def set_checksum_cache(checksums)
    end

    def next_seq
      @seq += 1
      "%08d" % @seq
    end

    def assign_id(prefix, filename)
      id = get_next_id(prefix)
      @fileids[$filename] = id
    end

    def add_file(filename, **attrs)
      if attrs[:id].nil?
        attrs[:id] = assign_id(attrs[:prefix], filename)
      end
      attrs[:seq] = next_seq if attrs[:seq].nil?
      attrs.delete(:seq) if attrs[:seq] == false
      path = attrs.delete(:path)
      # checksum path logic...
      file = METS::File.new(self, **attrs)
      file.set_local_file(filename, path)
      # if items then
      #   items.each do |item|
      #     STDERR.puts "?? #{item['href']}"
      #     subfile = file.add_sub_file(item['href'])
      #   end
      # end
      @components << file
    end

    def add_files(filenames, **attrs)
      filenames.each do |filename|
        add_file(filename, **attrs)
      end
    end

    def add_file_group(filegroup)
    end

    def get_next_id(prefix=nil)
      STDERR.puts "ASSIGNER #{@assigner} :: #{prefix}"
      if @assigner
        return @assigner.next_id(prefix)
      end
      prefix = "" if prefix.nil?
      @prefix_counts[prefix] += 1
      prefix + ( "%08d" % @prefix_counts[prefix] )
    end

    def to_node
      node = METS.create_element('fileGrp', @attrs)
      @components.each do |item|
        node << item.to_node
      end
      node
    end

  end
end
