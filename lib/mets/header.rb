require 'nokogiri'
require 'mets'

module METS
	class Header
		def initialize(**attrs)
			@attrs = METS.copy_attributes(attrs, %w{ID ADMID CREATEDATE LASTMODDATE RECORDSTATUS})
			@agents = []
			@alt_record_ids = []
			@mets_document_id = nil
		end

		def add_agent(**attrs)
			name = attrs[:name]
			notes = attrs[:notes]

			METS.check_attr_val(attrs[:type], METS::ALLOWED_AGENT_TYPE)
			METS.check_attr_val(attrs[:role], METS::ALLOWED_AGENT_ROLE)

			agent_node = METS.create_element("agent",
				METS.copy_attributes(attrs, %w{ID ROLE OTHERROLE TYPE OTHERTYPE}))

			unless name.nil?
				name_node = METS.create_element("name", nil, name)
				agent_node << name_node
			end

			unless notes.nil?
				notes.each do |note|
					agent_node << METS.create_element("note", nil, note)
				end
			end

			@agents << agent_node
		end

		def add_alt_record_id(alt_record_id, **attrs)
			@alt_record_ids << METS.create_element(
				"altRecordID", METS.copy_attributes(attrs, %w{ID TYPE}), alt_record_id)
		end

		def set_mets_document_id(document_id, id, type)
			@mets_document_id = METS.create_element(
				"metsDocumentID",
				{ ID: id, TYPE: type },
				document_id
			)
		end

		def to_node
			node = METS.create_element("metsHdr", @attrs)

			@agents.each do |agent_node|
				node << agent_node
			end

			@alt_record_ids.each do |alt_record_id|
				node << alt_record_id
			end

			node << @mets_document_id unless @mets_document_id.nil?

			node
		end

	end
end
