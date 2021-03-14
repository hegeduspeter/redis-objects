require File.dirname(__FILE__) + '/base_object'

class Redis
  #
  # Class representing a Redis counter.  This functions like a proxy class, in
  # that you can say @object.counter_name to get the value and then
  # @object.counter_name.increment to operate on it.  You can use this
  # directly, or you can use the counter :foo class method in your
  # class to define a counter.
  #
  class Integer < BaseObject
    def initialize(key, *args)
      super(key, *args)
      raise ArgumentError, "Marshalling redis integers does not make sense" if @options[:marshal]
      redis.setnx(key, @options[:default]) unless @options[:init] === false
    end

    # Reset the counter to its starting value.  Not atomic, so use with care.
    # Normally only useful if you're discarding all sub-records associated
    # with a parent and starting over (for example, restarting a game and
    # disconnecting all players).
    def reset(to=options[:default])
      allow_expiration do
        redis.set key, to.to_i
        true  # hack for redis-rb regression
      end
    end

    # Reset the counter to its starting value, and return previous value.
    # Use this to "reap" the counter and save it somewhere else. This is
    # atomic in that no increments or decrements are lost if you process
    # the returned value.
    def getset(to=options[:default])
      redis.getset(key, to.to_i).to_i
    end

    # Returns the current value of the counter.  Normally just calling the
    # counter will lazily fetch the value, and only update it if increment
    # or decrement is called.  This forces a network call to redis-server
    # to get the current value.
    def value
      redis.get(key).to_i
    end
    alias_method :get, :value

    def value=(val)
      allow_expiration do
        if val.nil?
          delete
        else
          redis.set key, val.to_i
        end
      end
    end
    alias_method :set, :value=

    # Like .value but casts to float since Redis addresses these differently.
    def to_f
      redis.get(key).to_f
    end

    ##
    # Proxy methods to help make @object.counter == 10 work
    def to_s; value.to_s; end
    alias_method :to_i, :value

    def nil?
      !redis.exists(key)
    end

    ##
    # Math ops
    # This needs to handle +/- either actual integers or other Redis::Counters
    %w(+ - == < > <= >=).each do |m|
      class_eval <<-EndOverload
        def #{m}(what)
          value.to_i #{m} what.to_i
        end
      EndOverload
    end

    private

  end
end
