require 'yaml'
require 'mime/types'
require 'net/http'
require 'uri'
require 'sequel'

require 'pathname'
require 'pp'
require 'nokogiri'

require 'inifile'

PARSE_OPTIONS = Nokogiri::XML::ParseOptions::DEFAULT_XML | Nokogiri::XML::ParseOptions::NOBLANKS
DLXS_SERVICE = "quod.lib.umich.edu"


module HaversackIt
  class Haversack

    attr_reader :db
    attr_reader :identifier_pathname

    def initialize(**args)
      config = IniFile.load("#{ENV['DLXSROOT']}/bin/i/image/etc/package.conf")
      @db = Sequel.connect(adapter: 'mysql2', host: 'mysql-quod', user: config['mysql']['user'], password: config['mysql']['password'], database: 'dlxs')
      @common = {}
      @source = {}
      @links = {}
      @metadata = {}
      @rights = {}
      @filegroups = {}
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
      build_filegroups
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
    def build_filegroups
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

      output_yaml(output_path, "common",   @common)
      output_yaml(output_path, "source",   @source)
      output_yaml(output_path, "links",    @links)
      output_yaml(output_path, "metadata", @metadata)
      output_yaml(output_path, "rights",   @rights)

      @filegroups.keys.each do |type|
        output_yaml(output_path, "files_#{type}", @filegroups[type])
      end

      @structmaps.keys.each do |type|
        output_yaml(output_path, "structmap_#{type}", @structmaps[type])
      end

      if @identifier_pathname
        @manifest.each do |file|
          if file.is_a?(Array)
            STDERR.puts "-- output: #{file[0]}"
            File.new(File.join(file_output_path, file[0]), "w").write(file[1])
          elsif file.is_a?(Pathname) and not File.symlink?(File.join(file_output_path, file.basename))
            STDERR.puts "-- linking: #{file.basename}"
            File.symlink(file, File.join(file_output_path, file.basename))
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
  end
end
