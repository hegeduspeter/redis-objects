require File.dirname(__FILE__) + '/base_object'

class Redis
  #
  # Class representing a Redis float.  This functions like a proxy class, in
  # that you can say @object.float_name to get the value and then
  # @object.float_name.increment to operate on it.  You can use this
  # directly, or you can use the float :foo class method in your
  # class to define a float.
  #
  class Float < BaseObject
    def initialize(key, *args)
      super(key, *args)
      raise ArgumentError, "Marshalling redis floats does not make sense" if @options[:marshal]
      redis.setnx(key, @options[:default]) unless @options[:default].nil? || @options[:init] === false
    end

    # Returns the current value of the float.
    def value
      redis.get(key).to_f
    end
    alias_method :get, :value

    def value=(val)
      return delete if val.nil?
      allow_expiration { redis.set key, val }
    end
    alias_method :set, :value=

    ##
    # Proxy methods to help make @object.float == 10 work
    def to_s; value.to_s; end
    alias_method :to_i, :value

    def nil?
      !redis.exists(key)
    end

    ##
    # Math ops
    # This needs to handle +/- either actual floats or other Redis::Floats
    %w(+ - == < > <= >=).each do |m|
      class_eval <<-EndOverload
        def #{m}(what)
          value.to_i #{m} what.to_i
        end
      EndOverload
    end

  end
end
