require 'spec_object'

class Foo
  def initialize
    @variables = {}
  end

  def get(k)
    @variables[k]
  end

  def del(k)
    @variables.delete(k)
    nil
  end

  def set(k, v)
    @variables[k] = v
    nil
  end
end

class FooSpec
  extend So::SpecObject

  specs Foo

  behaviour :del do |args, output|
    output == nil
  end

  behaviour :set do |args, output|
    output == nil
  end

  behaviour :get do |args, output|
    key = args[0]

    ite(
      output == nil,
      begin
        key_deleted =
          exist do |delete_time|
            both(
              received(:del).at(delete_time).with(key),
              !exist do |set_time|
                both(
                  set_time > delete_time,
                  exist do |value|
                    received(:set).at(set_time).with(key, value)
                  end
                )
              end
            )
          end

        key_never_set =
          !exist do |set_time|
            exist do |value|
              received(:set).at(set_time).with(key, value)
            end
          end

        either(
          key_deleted,
          key_never_set
        )
      end,
      exist do |set_time|
        key_set_at_set_time =
          received(:set).at(set_time).with(key, output)

        key_not_set_later =
          !exist do |later_set_time|
            both(
              later_set_time > set_time,
              exist do |value|
                received(:set).at(later_set_time).with(key, value)
              end
            )
          end

        key_not_deleted_later =
          !exist do |later_delete_time|
            both(
              later_delete_time > set_time,
              received(:del).at(later_delete_time).with(key)
            )
          end

        all(
          key_set_at_set_time,
          key_not_set_later,
          key_not_deleted_later
        )
      end
    )
  end
end

f = Foo.new
f.set(:foo, :bar)
f.set(:foo, 5)
f.get(:foo)
