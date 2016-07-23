class Object
  def to_so_expr
    So::Const.new(self)
  end
end

module So
  class Expr
    def to_so_expr
      self
    end

    def <(other)
      Lt.lt(self, other)
    end

    def >(other)
      Lt.lt(other, self)
    end

    def !
      Not.not_(self)
    end

    def ==(other)
      Eq.eq(self, other)
    end

    def [](key)
      Index.index(self, key)
    end

    def assert_time
    end

    def assert_value
    end
  end

  class Const < Expr
    def initialize(value)
      @value = value
    end

    attr_reader :value

    def pp(n)
      "#{' '*n}#{@value.inspect}"
    end

    def substitute(v, e)
      self
    end

    def evaluate(calls)
      self
    end
  end

  class Time < Expr
    def initialize(n)
      @n = n
    end

    attr_reader :n

    def pp(n)
      "#{' '*n}t#{@n}"
    end

    def substitute(v, e)
      self
    end

    def evaluate(calls)
      self
    end
  end

  class Variable < Expr
    def initialize
      @is_time = false
      @is_value = false
    end

    def time?
      @is_time
    end

    def value?
      @is_value
    end

    def pp(n)
      "#{' '*n}v#{object_id}"
    end

    def substitute(v, e)
      if v.object_id == self.object_id
        e
      else
        self
      end
    end

    def evaluate(calls)
      self
    end

    def assert_value
      @is_value = true
      raise "variable used as both value and time" if @is_time
    end

    def assert_time
      @is_time = true
      raise "variable used as both value and time" if @is_value
    end
  end

  class Lt < Expr
    def initialize(a, b)
      @a = a
      @b = b
    end

    def self.lt(a, b)
      a = a.to_so_expr
      b = b.to_so_expr

      if a.kind_of?(Const) && b.kind_of?(Const)
        a.value < b.value
      elsif a.kind_of?(Time) && b.kind_of?(Time)
        a.n < b.n
      else
        new(a, b)
      end
    end

    def pp(n)
      "#{' '*n}(<\n#{@a.pp(n+2)}\n#{@b.pp(n+2)})"
    end

    def substitute(v, e)
      Lt.lt(@a.substitute(v, e), @b.substitute(v, e))
    end

    def evaluate(calls)
      Lt.lt(@a.evaluate(calls), @b.evaluate(calls))
    end
  end

  class Eq < Expr
    def initialize(a, b)
      @a = a
      @b = b
    end

    def self.eq(a, b)
      a = a.to_so_expr
      b = b.to_so_expr

      if a.kind_of?(Const) && b.kind_of?(Const)
        (a.value == b.value).to_so_expr
      else
        new(a, b)
      end
    end

    def pp(n)
      "#{' '*n}(==\n#{@a.pp(n+2)}\n#{@b.pp(n+2)})"
    end

    def substitute(v, e)
      Eq.eq(@a.substitute(v, e), @b.substitute(v, e))
    end
  end

  class Index < Expr
    def initialize(x, index)
      @x = x
      @index = index
    end

    def self.index(x, index)
      x = x.to_so_expr
      index = index.to_so_expr

      if x.kind_of?(Const) && index.kind_of?(Const)
        (x.value[index.value]).to_so_expr
      else
        new(x, index)
      end
    end

    def pp(n)
      "#{@x.pp(n)}[#{@index.pp(0)}]"
    end

    def substitute(v, e)
      Index.index(@x.substitute(v, e), @index.substitute(v, e))
    end
  end

  class And < Expr
    def initialize(*args)
      @args = args
    end

    def self.and_(*args)
      args.map! do |arg|
        arg.to_so_expr
      end

      args1 =
        args.select do |arg|
          if arg.kind_of?(Const)
            if arg.value == false
              return arg
            elsif arg.value == true
              false
            else
              true
            end
          else
            true
          end
        end

      if args1.size == 1
        args1[0]
      elsif args1.size == 0
        true.to_so_expr
      else
        new(*args1)
      end
    end

    def pp(n)
      s = @args.map do |arg| arg.pp(n+2) end.join("\n")
      "#{' '*n}(and\n#{s})"
    end

    def substitute(v, e)
      And.and_(*@args.map do |arg| arg.substitute(v, e) end)
    end

    def evaluate(calls)
      And.and_(*@args.map do |arg| arg.evaluate(calls) end)
    end
  end

  class Not < Expr
    def initialize(x)
      @x = x
    end

    attr_reader :x

    def self.not_(x)
      x = x.to_so_expr

      if x.kind_of?(Const)
        (!(x.value)).to_so_expr
      elsif x.kind_of?(Not)
        x.x
      else
        new(x)
      end
    end

    def pp(n)
      "#{' '*n}(not\n#{@x.pp(n+2)})"
    end

    def substitute(v, e)
      Not.not_(@x.substitute(v, e))
    end

    def evaluate(calls)
      Not.not_(@x.evaluate(calls))
    end
  end

  class Exists < Expr
    def initialize(variable, expr)
      raise "expected variable" unless variable.is_a?(Variable)

      @variable = variable
      @expr = expr.to_so_expr
    end

    def pp(n)
      "#{' '*n}(exists #{@variable.pp(0)}\n#{@expr.pp(n+2)})"
    end

    def substitute(v, e)
      raise "bad thing happ(n)ened" if v.object_id == @variable.object_id
      Exists.new(@variable, @expr.substitute(v, e))
    end

    def evaluate(calls)
      if @variable.time?
        posibilities =
          (0...calls.size).map do |t|
            v = @expr.substitute(@variable, Time.new(t)).evaluate(calls)
          end

        t =
          posibilities.any? do |v|
            v.kind_of?(Const) && v.value
          end

        if t
          true.to_so_expr
        else
          f =
            posibilities.all? do |v|
              v.kind_of?(Const) && !(v.value)
            end

          if f
            false.to_so_expr
          else
            self
          end
        end
      elsif @variable.value?
        self
      else
        raise "cannot infer the type of #{@variable.pp(0)}"
      end
    end
  end

  class Received < Expr
    def initialize(method, time=nil, args=nil)
      raise "expected method name" unless method.is_a?(Symbol)

      @method = method
      @time = time
      @args = args
    end

    def at(time)
      time = time.to_so_expr
      time.assert_time
      r = Received.new(@method, time, @args)
      r
    end

    def with(*args)
      args.map! do |arg|
        arg.assert_value
        arg.to_so_expr
      end
      Received.new(@method, @time, args)
    end

    def pp(n)
      s = 
        if !(@args.nil?)
          @args.map do |arg| arg.pp(n+4) end.join("\n")
        else
          "#{' '*(n+2)}"
        end
      t_pp =
        if !(@time.nil?)
          @time.pp(n+2)
        else
          "#{' '*(n+2)}nil"
        end
      "#{' '*n}(received #{@method.inspect}\n#{t_pp}\n#{' '*(n+2)}(\n#{s}))"
    end

    def substitute(v, e)
      time = @time.substitute(v, e)
      args = @args.map do |arg| arg.substitute(v, e) end

      Received.new(@method, time, args)
    end

    def evaluate(calls)
      t = @time.evaluate(calls)
      if !(t.kind_of?(Time))
        return self
      end

      method, args, output = calls[t.n]
      if method != @method
        return false.to_so_expr
      end

      if args.size != @args.size
        return false.to_so_expr
      end

      exprs =
        args.zip(@args).map do |(value, expr)|
          value.to_so_expr == expr
        end

      And.and_(*exprs)
    end
  end

  class DSL
    def exist(&blk)
      v = Variable.new
      Exists.new(v, blk.call(v))
    end

    def received(method)
      Received.new(method)
    end

    def both(a, b)
      And.and_(a, b)
    end

    def all(*args)
      And.and_(*args)
    end

    def either(a, b)
      a = a.to_so_expr
      b = b.to_so_expr

      !both(!a, !b)
    end

    def ite(c, t, f)
      c = c.to_so_expr

      either(both(c, t), both(!c, f))
    end
  end

  module SpecObject
    def self.extended(mod)
      mod.send(:define_singleton_method, :behaviours) do
        @behaviours ||= {}
      end

      mod.send(:define_method, :initialize) do |wrapped|
        @wrapped = wrapped
        @calls = []
      end

      mod.send(:define_method, :method_missing) do |name, *args|
        output = @wrapped.send(name, *args)

        behaviour = mod.behaviours[name]
        if behaviour
          v_args, v_output, expr = behaviour.values_at(:args, :output, :expr)

          expr =
            expr
              .substitute(v_output, output.to_so_expr)
              .substitute(v_args, args.to_so_expr)

          v = expr.evaluate(@calls)
          unless v.kind_of?(Const) && v.value
            puts v.pp(0)
            raise "Problem"
          end
        end

        @calls.push([name, args, output])

        output
      end
    end

    def specs(cl)
      spec = self

      old_new = cl.method(:new)
      cl.send(:define_singleton_method, :new) do |*args|
        spec.new(old_new.call(*args))
      end
    end

    def behaviour(name, &blk)
      args = Variable.new
      output = Variable.new

      expr = DSL.new.instance_exec(args, output, &blk).to_so_expr

      behaviours[name] = {
        args: args,
        output: output,
        expr: expr
      }
    end
  end
end
