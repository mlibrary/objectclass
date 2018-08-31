require 'nokogiri'

require 'mets'

module METS
	class Subfile < METS::File
		def compute_md5_checksum
			# do not compute
		end

		# def loctype
		# 	{ LOCTYPE: 'URL' }
		# end

		def set_local_file(filename)
			@local_file = filename
		end
	end
end
