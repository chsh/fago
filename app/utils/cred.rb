class Cred
  class EnvRef
    def self.hash_from_key(key)
      @@key_to_hash ||= {}
      @@key_to_hash[key] ||= build_hash(key)
    end

    private
    def self.build_hash(key)
      r = {}
      matched_keys = ENV.keys.grep(/^#{key.upcase}_/)
      matched_keys.each do |matched_key|
        new_key = matched_key.gsub(/^#{key.upcase}_/, '').downcase
        r[new_key.to_sym] = ENV[matched_key]
      end
      r
    end
  end

  concerning :AliasFeature do
    class_methods do
      def method_missing(key)
        self.class.class_eval {
          define_method key do
            EnvRef.hash_from_key(key).reverse_merge(Rails.application.credentials.send(key) || {})
          end
        }
        send key
      end
    end
  end
end
