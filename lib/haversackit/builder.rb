require 'pp'
require 'nokogiri'
require 'haversackit/bag'
require 'fileutils'
require 'yaml'

require 'mime/types'
require 'mets'

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
			@mets = METS::Document.new objid: @objid
			@assigner = Assigner.new
			@sources = {}
			@amdsecs = []
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

			# bag.add_file("README.txt") do |io|
			# 	io.puts "Hello: #{Time.now.strftime("%Y-%m-%d %H:%M:%S")}"
			# end

			bag.add_file("#{@identifier}/#{@identifier}.mets.xml") do |io|
				io.puts to_xml
			end

			FileUtils.cd(@input_pathname) do
				Dir.glob("files/**/*.*").each do |input_filename|
					# filename = input_filename.sub(builder.input_pathname, '')
					# filename = filename[1..-1] if filename[0] == '/'
					STDERR.puts "#{input_filename} :: #{File.symlink?(input_filename) ? '*' : ':'}"
					if File.symlink?(input_filename)
						true_filename = File.readlink(input_filename)
						bag.add_symlink(File.join(@identifier, input_filename), true_filename)
					else
						bag.add_file(File.join(@identifier, input_filename), input_filename)
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

			data = source[:data]
			builder = Nokogiri::XML::Builder.new do |xml|
				xml.root('xmlns:dcterms' => 'http://purl.org/dc/terms/') {
					data.keys.each do |key|
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
			source = @sources[:links]
			return unless source

			data = source[:data]
			if data['memberOf']
				builder = Nokogiri::XML::Builder.new do |xml|
					xml.root('xmlns:dcterms' => 'http://purl.org/dc/terms/', 'xmlns:dcam' => 'http://purl.org/dc/dcam/') {
						data["memberOf"].each do |urn|
							xml['dcam'].memberOf urn
						end
					}
				end

				nodes = builder.doc.root.element_children
				dmd_sec = METS::MetadataSection.new 'dmdSec', id: 'DMDCOLLECTIONS'
				dmd_sec.set_xml_node(nodes, mdtype: 'DC', label: 'In Collections')
				@mets.add_dmd_sec(dmd_sec)
			end

			if data['isPartOf']
				label = 'Part Of'
				builder = Nokogiri::XML::Builder.new do |xml|
					xml.root('xmlns:dcterms' => 'http://purl.org/dc/terms/', 'xmlns:dcam' => 'http://purl.org/dc/dcam/') {
						items = data["isPartOf"].is_a?(Array) ? data["isPartOf"] : data["isPartOf"]["items"]
						attrs = data["isPartOf"].is_a?(Array) ? {} : data["isPartOf"]
						if attrs["type"]
							xml['dcterms'].type attrs["type"]
						end
						items.each do |urn|
							xml['dcterms'].isPartOf urn
						end
					}
				end
				nodes = builder.doc.root.element_children
				dmd_sec = METS::MetadataSection.new 'dmdSec', id: 'DMDPARTS'
				dmd_sec.set_xml_node(nodes, mdtype: 'DC', label: label)
				@mets.add_dmd_sec(dmd_sec)
			end
		end

		def build_metadata_dmdsec
			source = @sources[:metadata]
			return unless source

			dmd_sec = METS::MetadataSection.new 'dmdSec', id: next_id('DMD')

			data = source[:data]
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
			else
				builder = Nokogiri::XML::Builder.new do |xml|
					xml.record('xmlns' => 'http://lib.umich.edu/dlxs/metadata') {
						data.keys.each do |key|
							xml.field(abbrev: key) {
								values = [ data[key] ].flatten
								values.each do |value|
									xml.value value
								end
							}
						end
					}
				end

				metadata_filename = "#{@objid}.metadata.xml"
				# then builder is written to this file

				params[:xlink] = { href: metadata_filename }
				params[:mdtype] = 'OTHER';
				params[:othermdtype] = 'DLXS ImageClass XML'
				params[:label] = 'Work Metadata'
				params[:loctype] = 'URL'
			end
			dmd_sec.set_md_ref(**params)
			@mets.add_dmd_sec(dmd_sec)
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
			return unless ( source = @sources[:source] ? @sources[:source][:data] : nil )
			amd_sec = METS::MetadataSection.new 'sourceMD', id: next_id('AMD')
			params = build_mdref(source)
			amd_sec.set_md_ref(**params)
			@amdsecs << amd_sec
		end

		def build_amdsec_digiprovmd
		end

		def build_filesec
			# basically anything that's not a YAML file?
			filegroups = @sources.select{ |key, value| key.to_s.start_with?('files_') }
			filegroups.each do |filename, files|
				use = filename.to_s.sub('files_', '')
				filegroup = METS::FileGroup.new id: next_id('FG'), use: use, assigner: @assigner
				files[:data].each_with_index do |file, seq|
					@fileidcache[[file['href']]] = next_id('FID')
					filegroup.add_file(
						"#{file['href']}",
						seq: file['seq'],
						path: File.join(@input_pathname),
						mimetype: file['mimetype'],
						id: @fileidcache[[file['href']]],
					)
					if file['files'] then
						file['files'].each_with_index do |subfile, subidx|
						# @fileidcache[[file['href'], subfile['href']]] = next_id('FID')
							@fileidcache[[subfile['href']]] = next_id('FID')
							seq = subfile['seq'] || "%08d" % (subidx + 1)
							filegroup.components[-1].add_sub_file(
								subfile['href'],
								id: @fileidcache[[subfile['href']]], # @fileidcache[[file['href'], subfile['href']]],
								seq: seq,
								loctype: subfile['loctype'],
								otherloctype: subfile['otherloctype']
							)
						end
					end
				end
				@mets.add_filegroup(filegroup)
			end
		end

		def build_structmap
			structmaps = @sources.select{ |key, value| key.to_s.start_with?('structmap_') }

			structmaps.each do |filename, value|
				type = filename.to_s.sub('structmap_', '')

				structmap = METS::StructMap.new type: type

				build_structmap_div(structmap, value[:data], order: false)

				@mets.add_struct_map(structmap)
			end
		end

		def build_structmap_div(parent, items, order: true)
			items.each_with_index do |item, seq|
				params = { type: item['type'], orderlabel: item['orderlabel'], label: item['label']}
				if order then
					params[:order] = item['seq'] || (seq + 1)
				end
				div = METS::StructMap::Div.new(**params)

				if item['files'] then
					item['files'].each do |file|
						hrefs = [ file['href'] ].flatten
						if file['href'].nil?
							PP.pp item, STDERR
						end
						if hrefs[0].start_with?('urn:') then
							div.add_mptr(href: hrefs[0])
						else
							fileid = @fileidcache[hrefs]
							div.add_fptr(fileid: fileid)
						end
					end
				end

				parent.add_div(div)

				if item['items'] then
					build_structmap_div(div, item['items'])
				end
			end
		end

		def xxbuild_structmap_div(parent, items, order: true)
			if items[0]['href'] then
				files = items.map{|v| v['href']}
				adding_mptr = items[0]['href'].start_with?('urn:')
				files.each do |filename|
					if adding_mptr then
						parent.add_mptr(href: filename)
					else
						fileid = @fileidcache[filename]
						parent.add_fptr(fileid: fileid)
					end
				end
			else
				items.each_with_index do |item, seq|
					params = { type: item['type'], orderlabel: item['orderlabel'], label: item['label']}
					if order then
						params[:order] = seq + 1
					end
					div = METS::StructMap::Div.new(**params)
					parent.add_div(div)
					build_structmap_div(div, item['items']) if item['items']
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

		def to_xml
			build_metadata
			@mets.to_node.to_s
		end

		def format_time(time)
			time.gmtime.strftime("%Y-%m-%dT%H:%M:%S")
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
