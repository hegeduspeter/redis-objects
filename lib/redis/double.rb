require File.dirname(__FILE__) + '/base_object'

class Redis
  #
  # Class representing a Redis double.  This functions like a proxy class, in
  # that you can say @object.double_name to get the value and then
  # @object.double_name.increment to operate on it.  You can use this
  # directly, or you can use the double :foo class method in your
  # class to define a double.
  #
  class Double < BaseObject
    # Returns the current value of the double.
    def value
      val = redis.get(key)
      val.nil? ? @options[:default] : val.to_f
    end
    alias_method :get, :value

    def value=(val)
      return delete if val.nil?
      allow_expiration { redis.set key, val }
    end
    alias_method :set, :value=

    ##
    # Proxy methods to help make @object.double == 10 work
    def to_s; value.to_s; end
    alias_method :to_f, :value

    def inspect
      "#<Redis::Double #{value.inspect}>"
    end

    def nil?
      !redis.exists(key)
    end

    def present?
      !nil?
    end

    ##
    # Math ops
    # This needs to handle +/- either actual doubles or other Redis::Doubles
    %w(+ - == < > <= >=).each do |m|
      class_eval <<-EndOverload
        def #{m}(what)
          value.to_f #{m} what.to_f
        end
      EndOverload
    end

    def method_missing(*args)
      self.value.send(*args)
    end

  end
end
