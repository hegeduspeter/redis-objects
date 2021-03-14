# This is the class loader, for use as "include Redis::Objects::Counters"
# For the object itself, see "Redis::Counter"
require 'redis/counter'
class Redis
  module Objects
    class UndefinedInteger < StandardError; end #:nodoc:
    class MissingID < StandardError; end #:nodoc:

    module Integers
      def self.included(klass)
        klass.instance_variable_set('@initialized_integers', {})
        klass.send :include, InstanceMethods
        klass.extend ClassMethods
      end

      # Class methods that appear in your class when you include Redis::Objects.
      module ClassMethods
        attr_reader :initialized_integers

        # Define a new counter.  It will function like a regular instance
        # method, so it can be used alongside ActiveRecord, DataMapper, etc.
        def integer(name, options={})
          redis_objects[name.to_sym] = options.merge(:type => :integer)
          ivar_name = :"@#{name}"

          mod = Module.new do
            define_method(name) do
              instance_variable_get(ivar_name) or
                instance_variable_set(ivar_name,
                  Redis::Integer.new(
                    redis_field_key(name), redis_field_redis(name), redis_options(name)
                  )
                )
            end
          end

          if options[:global]
            extend mod

            # dispatch to class methods
            define_method(name) do
              self.class.public_send(name)
            end
          else
            include mod
          end
        end

        # Get the current value of the counter. It is more efficient
        # to use the instance method if possible.
        def get_integer(name, id=nil)
          verify_integer_defined!(name, id)
          redis.get(redis_field_key(name, id)).to_i
        end

        def integer_defined?(name) #:nodoc:
          redis_objects && redis_objects.has_key?(name.to_sym)
        end

        private

        def verify_integer_defined!(name, id) #:nodoc:
          raise NoMethodError, "Undefined integer :#{name} for class #{self.name}" unless integer_defined?(name)
          if id.nil? and !redis_objects[name][:global]
            raise Redis::Objects::MissingID, "Missing ID for non-global integer #{self.name}##{name}"
          end
        end
      end

      # Instance methods that appear in your class when you include Redis::Objects.
      module InstanceMethods
      end

    end
  end
end
