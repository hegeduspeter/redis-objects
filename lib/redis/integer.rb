require File.dirname(__FILE__) + '/base_object'

class Redis
  #
  # Class representing a Redis integer.  This functions like a proxy class, in
  # that you can say @object.integer_name to get the value and then
  # @object.integer_name.increment to operate on it.  You can use this
  # directly, or you can use the integer :foo class method in your
  # class to define a integer.
  #
  class Integer < BaseObject
    # Returns the current value of the integer.
    def value
      val = redis.get(key)
      val.nil? ? @options[:default] : val.to_i
    end
    alias_method :get, :value

    def value=(val)
      return delete if val.nil?
      allow_expiration { redis.set key, val }
    end
    alias_method :set, :value=

    # Like .value but casts to float since Redis addresses these differently.
    def to_f
      redis.get(key).to_f
    end

    ##
    # Proxy methods to help make @object.integer == 10 work
    def to_s; value.to_s; end
    alias_method :to_i, :value

    def inspect
      "#<Redis::Integer #{value.inspect}>"
    end

    def nil?
      !redis.exists(key)
    end

    ##
    # Math ops
    # This needs to handle +/- either actual integers or other Redis::Integers
    %w(+ - == < > <= >=).each do |m|
      class_eval <<-EndOverload
        def #{m}(what)
          value.to_i #{m} what.to_i
        end
      EndOverload
    end

    def method_missing(*args)
      self.value.send(*args)
    end

  end
end
