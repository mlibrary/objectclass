require 'nokogiri'
require 'mets/header'
require 'mets/metadata_section'
require 'mets/file'
require 'mets/subfile'
require 'mets/file_group'
require 'mets/struct_map'
require 'mets/checksum_cache'

require 'pp'

# METS - library to create METS XML.

# my $mets = METS->new(...);

# $mets->set_header(...);
# $mets->add_dmd_sec(...);
# $mets->add_amd_sec(...);
# $mets->add_filegroup(...);
# $mets->add_struct_map(...);

# print $mets->to_node()->toString();

# khead1 DESCRIPTION

# This module assists with creating XML documents following the Metadata Encoding
# & Transmission Standards (METS) schema from the Library of Congress. Most major
# features of METS are supported.

# See L<the METS home page|http://www.loc.gov/standards/mets/> for more
# information.

module METS
	NS_METS        = "http://www.loc.gov/METS/"
	NS_prefix_METS = "METS"
	SCHEMA_METS    = "http://www.loc.gov/standards/mets/mets.xsd"
	NS_prefix_xlink = "xlink"
	NS_xlink       = "http://www.w3.org/1999/xlink"
	NS_prefix_xsi = "xsi"
	NS_xsi         = "http://www.w3.org/2001/XMLSchema-instance"
	NS_prefix_htpremis  = "HTPREMIS"
	NS_htpremis 	= "http://www.hathitrust.org/premis_extension"
	NS_prefix_ht= "HT"
	NS_ht = "http://www.hathitrust.org/ht_extension"
	NS_prefix_dlxs="dlxs"
	NS_dlxs = "http://lib.umich.edu/dlxs_extension"
	NS_dc = 'http://purl.org/dc/terms/'
	NS_prefix_dc = 'dcterms'
	NS_dcam = 'http://purl.org/dc/dcam/'
	NS_prefix_dcam = 'dcam'
	NS_mods = 'http://www.loc.gov/mods/v3'
	NS_prefix_mods = 'mods'
	LOCATION = ['LOCTYPE',  'OTHERLOCTYPE' ]
	METADATA = [ 'MDTYPE',   'OTHERMDTYPE', 'MDTYPEVERSION' ]
	FILECORE = [ 'MIMETYPE', 'SIZE', 'CREATED', 'CHECKSUM', 'CHECKSUMTYPE' ]

	ALLOWED_AGENT_TYPE = %w(INDIVIDUAL ORGANIZATION);
	ALLOWED_AGENT_ROLE = %w(CREATOR EDITOR ARCHIVIST PRESERVATION DISSEMINATOR CUSTODIAN IPOWNER);

	ALLOWED_LOCTYPE = %w(ARK URN URL PURL HANDLE DOI OTHER);
	ALLOWED_MDTYPE = %w(MARC MODS EAD DC NISOIMG LC-AV VRA TEIHDR DDI FGDC LOM PREMIS PREMIS:OBJECT PREMIS:AGENT PREMIS:RIGHTS PREMIS:EVENT TEXTMD METSRIGHTS ISO 19115:2003 NAP OTHER);

	# class << self
	# 	attr_accessor :allowed_AGENT_ROLE
	# 	attr_accessor :allowed_AGENT_TYPE
	# end

	class Document

		attr_accessor :header

		def initialize(**attrs)
			@doc = Nokogiri::XML::Document.new
			@attrs = METS.copy_attributes(attrs, %w{ID OBJID LABEL TYPE PROFILE})
			@header = nil
			@schemas = []
			@filegroups = []
			@structmaps = []
			@dmdsecs = []
			@amdsecs = []
		end

		def add_schema(prefix, ns, schema)
			@schemas << [ prefix, ns, schema ]
		end

		def to_node
			mets_node = METS.create_element("mets", @attrs)

			# schemas
			schema_locations = ["#{METS::NS_METS} #{METS::SCHEMA_METS}"]
			@schemas.each do |prefix, ns, schema|
				mets_node.add_namespace(prefix, ns)
				schema_locations << "#{ns} #{schema}" unless schema.nil?
			end

	    # set utility namespaces that don't have associated schemata
			mets_node.add_namespace(METS::NS_prefix_xlink, METS::NS_xlink)
			mets_node.add_namespace(METS::NS_prefix_xsi, METS::NS_xsi)
			mets_node.add_namespace(METS::NS_prefix_ht, METS::NS_ht)
			mets_node.add_namespace(METS::NS_prefix_htpremis, METS::NS_htpremis)
			mets_node.add_namespace(METS::NS_prefix_dlxs, METS::NS_dlxs)
			mets_node.add_namespace(METS::NS_prefix_dc, METS::NS_dc)
			mets_node.add_namespace(METS::NS_prefix_dcam, METS::NS_dcam)
			mets_node.add_namespace(METS::NS_prefix_mods, METS::NS_mods)

			unless schema_locations.empty?
				mets_node["xsi:schemaLocation"] = schema_locations.join(" ")
			end

			mets_node << METS.object_or_node_to_node(header) unless header.nil?

			@dmdsecs.each do |dmdsec|
				mets_node << METS.object_or_node_to_node(dmdsec)
			end

			# amdsec
			unless @amdsecs.empty?
				# @amdsecs.each do |amdsec|
				# 	mets_node << METS.object_or_node_to_node(amdsec)
				# end
				@amdsecs.each do |amdsec|
					amdsec_node = METS.create_element('amdSec', { ID: amdsec[:id] } )
					mets_node << amdsec_node
					amdsec[:sections].each do |mdsec|
						amdsec_node << METS.object_or_node_to_node(mdsec)
					end
				end
			end

			unless @filegroups.empty?
				filesec_node = METS.create_element('fileSec')
				mets_node << filesec_node
				@filegroups.each do |filegroup|
					filesec_node << METS.object_or_node_to_node(filegroup)
				end
			end

			unless @structmaps.empty?
				@structmaps.each do |structmap|
					mets_node << METS.object_or_node_to_node(structmap)
				end
			end

			@doc.root = mets_node
			@doc
		end

		def add_dmd_sec(section)
			@dmdsecs << section
		end

		def add_amd_sec(id, *sections)
			@amdsecs << { id: id, sections: sections }
		end
		# def add_amd_sec(section)
		# 	@amdsecs << section
		# end

		def add_struct_map(structmap)
			@structmaps << structmap
		end

		def add_filegroup(filegroup)
			@filegroups << filegroup
		end
	end

	# class methods
	def self.create_element(name, attributes=nil, text=nil)
		node = Nokogiri::XML::Node.new "#{NS_prefix_METS}:#{name}", Nokogiri::XML::DocumentFragment.parse("")
		node.add_namespace(NS_prefix_METS, NS_METS)
		unless attributes.nil?
			attributes.keys.each do |key|
				if key.to_s.start_with?('xmlns:')
					node.add_namespace(key.to_s.gsub('xmlns:',''), attributes[key])
				else
					node[key] = attributes[key] unless ( attributes[key].nil? )
				end
			end
		end
		unless text.nil?
			node.content = text
		end
		node
	end

	def self.copy_attributes(attrs_in, attrs_names)
		attrs_out = {}
		attrs_names.flatten.each do |attr_name|
			source_attr_name = attr_name.downcase.to_sym
			value = attrs_in[source_attr_name]
			next if value.nil?
			next if value.respond_to?(:empty?) and value.empty?
			attrs_out[attr_name.to_sym] = value
		end
		attrs_out
	end

	def self.check_attr_val(attr, allowed_vals)
		return true if attr.nil?
		allowed_vals.each do |allowed|
			return true if ( allowed == attr )
		end
		# raise exception for unexpected attribute value $attr
	end

	def self.object_or_node_to_node(thing)
		thing.respond_to?(:to_node) ? thing.to_node : thing
	end

	def self.set_xlink(node, xlink_attrs)
		xlink_attrs.each do |attr, value|
			if false and attr.to_s == 'type'
				node[attr] = value
			else
				node.add_namespace_definition("xlink", NS_xlink)
				node["xlink:#{attr}"] = value
			end
		end
	end

end
