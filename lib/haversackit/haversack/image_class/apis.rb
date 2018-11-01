module HaversackIt
  class Haversack
    class ImageClass
      class APIS < Haversack::ImageClass
        def update_caption_keys
          @caption_keys.delete(:apis_inv)
          @not_caption_keys[:apis_inv] = true
        end
      end
    end
  end
end


