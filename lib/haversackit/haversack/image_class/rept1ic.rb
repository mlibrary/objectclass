module HaversackIt
  class Haversack
    class ImageClass
      class REPT1IC < Haversack::ImageClass
        def build_structmaps
          seq = 0
          { 'SUMM' => 'MAP', 'DET' => 'X-RAY' }.each do |istruct_stty, label|

            seq += 1
            medium = @media.select{|v| v[:istruct_stty] == istruct_stty}.first
            @structmaps["display"] << {
              "label" => medium[:m_iid],
              "type" => label,
              "seq" => seq,
              "idref" => "#{@collid}:#{medium[:m_id]}:#{medium[:m_iid]}",
              "files" => [
                {
                  "href" => "urn:umich:x-asset:#{@collid}:#{medium[:m_fn]}"
                }
              ]
            }
          end
        end
      end
    end
  end
end


