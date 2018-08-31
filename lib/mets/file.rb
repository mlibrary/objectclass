require 'nokogiri'

require 'mets'

module METS
	class File

		MIME_MAP = {
			'zip' => 'application/zip',
			'jpg' => 'image/jpeg',
			'tif' => 'image/tiff',
			'jp2' => 'image/jp2',
			'txt' => 'text/plain',
			'html' => 'text/html',
			'xml' => 'text/xml',
			'pdf' => 'application/pdf',
		}

		def initialize(filegroup, **attrs)
			@attrs = METS.copy_attributes(attrs,
				['ID', 'SEQ', METS::FILECORE, 'OWNERID', 'ADMID', 'DMDID', 'GROUPID', 'USE', 'BEGIN', 'END', 'BETYPE']
			)
			@loctype = attrs[:loctype] || 'URL'
			@otherloctype = attrs[:otherloctype]
			@components = []
			@filegroup = filegroup
		end

		def set_local_file(local_file, path=nil)
			@local_file = local_file
			@path = path or "."
			compute_md5_checksum if @attrs[:CHECKSUM].nil?
			if @attrs[:SIZE].nil? or @attrs[:CREATED].nil?
				stat = ::File.stat(::File.join(@path, @local_file))
				size = stat.size
				mtime = stat.mtime.gmtime.strftime("%Y-%m-%dT%H:%M:%SZ")
				@attrs[:SIZE] = size unless @attrs[:SIZE]
				@attrs[:CREATED] = mtime unless @attrs[:CREATED]
			end
			@attrs[:MIMETYPE] = get_mimetype unless @attrs[:MIMETYPE]
		end

		def compute_md5_checksum
			require 'digest'
			file = ::File.join(@path, @local_file)
			data = ::File.read(file)
			digest = Digest::MD5.hexdigest data
			@attrs[:CHECKSUM] = digest
			@attrs[:CHECKSUMTYPE] = 'MD5'
		end

		def to_node
			node = METS.create_element('file', @attrs)
			if @local_file
				flocat = METS.create_element('FLocat', loctype)
				# need to do some scaping
				METS.set_xlink(flocat, { href: @local_file })
				node << flocat
			end
			@components.each do |item|
				node << item.to_node
			end
			node
		end

		def loctype
			# { LOCTYPE: 'OTHER', OTHERLOCTYPE: 'SYSTEM' }
			{ LOCTYPE: @loctype, OTHERLOCTYPE: @otherloctype }
		end

		def get_mimetype
			filename = @local_file
			suffix = filename.split('.')[-1]
			if suffix and MIME_MAP[suffix]
				return MIME_MAP[suffix]
			end
			"application/octet-stream"
		end

		def add_sub_file(filename, **attrs)
			attrs[:seq] = @filegroup.next_seq unless attrs[:seq]
			unless attrs[:id] then
				attrs[:id] = @filegroup.assign_id(attrs[:prefix], filename)
			end
			subfile = METS::Subfile.new(filename, **attrs)
			@components << subfile
			subfile.set_local_file(filename)
		end

	end
end
