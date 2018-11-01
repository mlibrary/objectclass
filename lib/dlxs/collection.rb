module DLXS
  class Collection

    attr_accessor :db, :config, :admin_map, :ic_id, :ic_vi, :reverse_ic_vi, :collid, :userid

    def initialize(collid:, db:, userid: nil)
      @db = db
      @collid = collid
      @userid = userid || ENV['DLPS_DEV'] || 'dlxsadm'

      load_config
    end

    private

  end
end
