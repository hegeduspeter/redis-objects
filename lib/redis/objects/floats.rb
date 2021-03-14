# This is the class loader, for use as "include Redis::Objects::Floats"
# For the object itself, see "Redis::Float"
require 'redis/float'
class Redis
  module Objects
    class UndefinedFloat < StandardError; end #:nodoc:
    class MissingID < StandardError; end #:nodoc:

    module Floats
      def self.included(klass)
        klass.send :include, InstanceMethods
        klass.extend ClassMethods
      end

      # Class methods that appear in your class when you include Redis::Objects.
      module ClassMethods

        # Define a new float.  It will function like a regular instance
        # method, so it can be used alongside ActiveRecord, DataMapper, etc.
        def float(name, options={})
          redis_objects[name.to_sym] = options.merge(:type => :float)
          ivar_name = :"@#{name}"

          mod = Module.new do
            define_method(name) do
              instance_variable_get(ivar_name) or
                instance_variable_set(ivar_name,
                  Redis::Float.new(
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

        # Get the current value of the float. It is more efficient
        # to use the instance method if possible.
        def get_float(name, id=nil)
          verify_float_defined!(name, id)
          redis.get(redis_field_key(name, id)).to_f
        end

        def float_defined?(name) #:nodoc:
          redis_objects && redis_objects.has_key?(name.to_sym)
        end

        private

        def verify_float_defined!(name, id) #:nodoc:
          raise NoMethodError, "Undefined float :#{name} for class #{self.name}" unless float_defined?(name)
          if id.nil? and !redis_objects[name][:global]
            raise Redis::Objects::MissingID, "Missing ID for non-global float #{self.name}##{name}"
          end
        end

      end

      # Instance methods that appear in your class when you include Redis::Objects.
      module InstanceMethods
      end
    end
  end
end
