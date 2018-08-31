require 'bagit'

module HaversackIt
	class Bag < BagIt::Bag
		# Add a bag symlink
		def add_symlink(base_path, src_path)
			path = File.join(data_dir, base_path)
			raise "Bag file exists: #{base_path}" if File.exist? path
			FileUtils::mkdir_p File.dirname(path)

			f = FileUtils::ln_s src_path, path
			write_bag_info
			return f
		end
	end
end
