require 'yaml'
require 'mime/types'
require 'net/http'
require 'uri'
require 'sequel'

require 'pathname'
require 'pp'
require 'nokogiri'

require 'fileutils'

require 'inifile'

require 'nanoid'

PARSE_OPTIONS = Nokogiri::XML::ParseOptions::DEFAULT_XML | Nokogiri::XML::ParseOptions::NOBLANKS
DLXS_SERVICE = "quod.lib.umich.edu"


module HaversackIt
  class Haversack

    attr_reader :db
    attr_reader :identifier_pathname, :idno
    attr_reader :common, :source, :links, :metadata, :rights, :filesets, :files, :structmaps, :manifest

    def initialize(**args)
      if args[:db]
        @db = args[:db]
      else
        config = IniFile.load("#{ENV['DLXSROOT']}/bin/i/image/etc/package.conf")
        @db = Sequel.connect(
          adapter: 'mysql2',
          host: config['mysql']['host'],
          user: config['mysql']['user'],
          password: config['mysql']['password'],
          port: config['mysql']['port'] || 3306,
          database: 'dlxs')
      end
      @common = {}
      @source = {}
      @links = {}
      @metadata = {}
      @rights = {}
      @filesets = []
      @files = {}
      @structmaps = {}

      @identifier_pathname = setup_identifier_pathname
      @manifest = []
    end

    def build
      fetch_data
      build_common
      build_metadata
      build_rights
      build_source
      build_links
      build_filesets
      build_structmaps
    end

    def fetch_data
    end
    def build_common
    end
    def build_metadata
    end
    def build_rights
    end
    def build_source
    end
    def build_links
    end
    def build_filesets
    end
    def build_structmaps
    end

    def save!(base_path)
      output_path = File.join(base_path, @idno)
      file_output_path = File.join(output_path, "files")

      unless Dir.exists?(output_path)
        Dir.mkdir(output_path, 0775)
        Dir.mkdir(file_output_path, 0775)
      end
      FileUtils.rm_f Dir.glob("#{output_path}/**/**")

      output_yaml(output_path, "common",   @common)
      output_yaml(output_path, "source",   @source)
      output_yaml(output_path, "links",    @links)

      @metadata = [@metadata].flatten
      @metadata.each do |metadatum|
        basename = "metadata"
        if metadatum['@id']
          basename += ".#{metadatum['@id']}"
        end
        output_yaml(output_path, basename, metadatum)
      end

      output_yaml(output_path, "rights",   @rights)

      output_yaml(output_path, "filesets", @filesets);

      # @filesets.keys.each do |type|
      #   output_yaml(output_path, "files_#{type}", @filesets[type])
      # end

      @structmaps.keys.each do |type|
        output_yaml(output_path, "structmap_#{type}", @structmaps[type])
      end

      if true or @identifier_pathname
        @manifest.each do |file|
          if file.is_a?(Array)
            STDERR.puts "-- output: #{file[0]}"
            File.new(File.join(file_output_path, file[0]), "w").write(file[1])
          elsif file.is_a?(Pathname) and not File.symlink?(File.join(file_output_path, file.basename))
            if @symlink
              STDERR.puts "-- linking: #{file.basename}"
              File.symlink(file, File.join(file_output_path, file.basename))
            else
              STDERR.puts "-- copying: #{file.basename}"
              FileUtils.cp(file, File.join(file_output_path, file.basename))
            end
          end
        end
      end
    end

    def output_yaml(output_path, basename, data)
      return if data.empty?
      STDERR.puts "-- #{basename}"
      File.new(File.join(output_path, "#{basename}.yaml"), "w").write(data.to_yaml)
    end

    def setup_identifier_pathname
    end

    def generate_id
      Nanoid.generate(alphabet: '1234567890abcdef')
    end
  end
end
