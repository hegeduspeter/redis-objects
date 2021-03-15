# This is the class loader, for use as "include Redis::Objects::Floats"
# For the object itself, see "Redis::Float"
require 'redis/float'
class Redis
  module Objects
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
            define_method("#{name}=") do |value|
              public_send(name).value = value.to_f
            end
          end

          if options[:global]
            extend mod

            # dispatch to class methods
            define_method(name) do
              self.class.public_send(name)
            end
            define_method("#{name}=") do |value|
              self.class.public_send("#{name}=", value.to_f)
            end
          else
            include mod
          end
        end
      end

      # Instance methods that appear in your class when you include Redis::Objects.
      module InstanceMethods
      end
    end
  end
end
