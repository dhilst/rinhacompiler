require 'json'
require "llvm/core"
require "llvm/execution_engine"

def makeop(op) 
  ->(a, b){ a.send(op, b) }
end

def eval_(node, env)
  case node
  in {kind: "Let", name: { text: }, value:, next: next_ }
    eval_(next_, env.merge({ text => value }))
  in {kind: "Function", parameters:, value:}
    pnames = parameters.map {|par| par[:text]}
    ->(*args) {
      eval_(
        value, env.merge(pnames.zip(args).to_h)
      )
    }
  in {kind: "Print", value: }
    puts(eval_(value, env))
  in {kind: "Call", callee:, arguments:}
    callee = eval_(callee, env)
    arguments = arguments.map {|arg| eval_(arg, env) }
    fail "not a function #{callee}" unless callee.respond_to? :call
    callee.call(*arguments)
  in {kind: "Var", text:}
    eval_(env[text], env)
  in {kind: "Int", value: value}
    Integer(value)
  in {kind: "Binary", lhs:, op:, rhs:}
    lhs = eval_(lhs, env)
    rhs = eval_(rhs, env)
    op = op.to_sym
    op_mapping = {
      Eq: makeop(:==),
      Or: makeop("||".to_sym),
      Sub: makeop(:-),
      Add: makeop(:+),
      Lt: makeop(:<),
    }
    fail "unbounded operator #{op} : #{op.class}" unless op_mapping.key? op
    op_mapping[op].call(lhs, rhs)
  in {kind: "If", condition:, then: then_, otherwise:}
    if eval_(condition, env)
      eval_(then_, env)
    else
      eval_(otherwise, env)
    end
  in cb if cb.respond_to? :call
    cb
  in x if [Integer, String, TrueClass, FalseClass].include?(x.class)
    x
  else
    fail "unexpected node #{node}"
  end
end

def indent(text, n, ts)
  text.to_s.split("\n").map do |text|
    "#{' ' * n * ts}#{text}"
  end.join("\n")
end

def compile_to_ruby(node)
  case node
  in {kind: "Let", name: { text: function_name }, value: { kind: "Function", parameters:, value: body }, next: next_ }
    parameters = parameters.map {|x| x[:text]}.join(",")
    <<~EOS
    def #{function_name}(#{parameters})
    #{indent(compile_to_ruby(body), 1, 2)}
    end

    #{compile_to_ruby(next_)}
    EOS
  in {kind: "Let", name: { text: }, value:, next: next_ }
    <<~EOS
    #{text} = #{compile_to_ruby(value)}
    #{compile_to_ruby(next_)}
    EOS
  in {kind: "Function", parameters:, value: body}
    pnames = parameters.map {|par| par[:text]}
    "->(#{pnames.join(',')}){ #{compile_to_ruby(body)} }"
  in {kind: "Print", value: }
    "puts(#{compile_to_ruby(value)})"
  in {kind: "Call", callee:, arguments:}
    callee = compile_to_ruby(callee)
    arguments = arguments.map {|arg| compile_to_ruby(arg) }.join(",")
    "#{callee}(#{arguments})"
  in {kind: "Var", text: name}
    name
  in {kind: "Int", value: value}
    value
  in {kind: "Binary", lhs:, op:, rhs:}
    lhs = compile_to_ruby(lhs)
    rhs = compile_to_ruby(rhs)
    op_mapping = {
      Eq: "==",
      Or: "||",
      Sub: "-",
      Add: "+",
      Lt: "<",
    }
    op = op_mapping[op.to_sym]

    "#{lhs} #{op} #{rhs}"
  in {kind: "If", condition:, then: then_, otherwise:}
    <<~EOS
      if #{compile_to_ruby(condition)}
        #{compile_to_ruby(then_)}
      else
        #{compile_to_ruby(otherwise)}
      end
    EOS
  else
    fail "unexpected node #{node}"
  end
end

def compile_to_python(node, context=nil)
  case node
  in {kind: "Let", name: { text: function_name }, value: { kind: "Function", parameters:, value: body }, next: next_ }
    parameters = parameters.map {|x| x[:text]}.join(",")
    <<~EOS
    def #{function_name}(#{parameters}):
    #{indent(compile_to_python(body, :function_body), 1, 4)}

    #{compile_to_python(next_)}
    EOS
  in {kind: "Let", name: { text: }, value:, next: next_ }
    <<~EOS
    #{text} = #{compile_to_python(value)}
    #{compile_to_python(next_, context)}
    EOS
  in {kind: "Function", parameters:, value: body}
    pnames = parameters.map {|par| par[:text]}
    case context
    when :function_body
      "return (lambda #{pnames.join(', ')}: #{compile_to_python(body)})"
    else
      "(lambda #{pnames.join(', ')}: #{compile_to_python(body)})"
    end
  in {kind: "Print", value: }
    case context 
    when :function_body
      "return print(#{compile_to_python(value)})"
    else
      "print(#{compile_to_python(value)})"
    end
  in {kind: "Call", callee:, arguments:}
    callee = compile_to_python(callee)
    arguments = arguments.map {|arg| compile_to_python(arg) }.join(", ")
    case context
    when :function_body
      "return #{callee}(#{arguments})"
    else
      "#{callee}(#{arguments})"
    end
  in {kind: "Var", text: name}
    case context
    when :function_body
      "return #{name}"
    else
      name
    end
  in {kind: "Int", value: value}
    case context
    when :function_body
      "return #{value}"
    else
      value
    end
  in {kind: "Binary", lhs:, op:, rhs:}
    lhs = compile_to_python(lhs)
    rhs = compile_to_python(rhs)
    op_mapping = {
      Eq: "==",
      Or: "or",
      Sub: "-",
      Add: "+",
      Lt: "<",
    }
    op = op_mapping[op.to_sym]

    case context
    when :function_body
      "return #{lhs} #{op} #{rhs}"
    else 
      "#{lhs} #{op} #{rhs}"
    end
  in {kind: "If", condition:, then: then_, otherwise:}
    <<~EOS
      if #{compile_to_python(condition)}:
      #{indent(compile_to_python(then_, context), 1, 4)}
      else:
      #{indent(compile_to_python(otherwise, context), 1, 4)}
    EOS
  else
    fail "unexpected node #{node}"
  end
end




def compile_to_llvm(node, mod, builder=nil)
  case node
  in {kind: "Let", name: { text: function_name }, value: { kind: "Function", parameters:, value: body }, next: next_ }
    mod.functions.add(function_name, parameters.map {|| LLVM::Int32 }, LLVM::Int32) do |function, string|
      function.basic_blocks.append.build do |b|
        compile_to_llvm(body, mod, b);
      end
    end
  in {kind: "Let", name: { text: }, value:, next: next_ }
    fail "todo Let"
  in {kind: "Function", parameters:, value: body}
    fail "todo Function"
  in {kind: "Print", value: }
    value = compile_to_llvm(value, mod, builder)
    cputs = mod.functions.add("puts", [LLVM.Pointer(LLVM::Int8)], LLVM::Int32) do |function, string|
      function.add_attribute :no_unwind_attribute
      string.add_attribute :no_capture_attribute
    end
    mod.functions.add("main", [], LLVM::Int32).basic_blocks.append.build do |b|
      hello = mod.globals.add(value, :hello) do |var|
        var.linkage = :private
        var.global_constant = true
        var.unnamed_addr = true
        var.initializer = value
      end

      zero = LLVM.Int(0) # a LLVM Constant value

      # Read here what GetElementPointer (gep) means http://llvm.org/releases/3.2/docs/GetElementPtr.html
      # Convert [13 x i8]* to i8  *...
      cast210 = b.gep(hello, [zero, zero], 'cast210')
      # Call puts function to write out the string to stdout.
      b.call(cputs, cast210)
      b.ret(LLVM::Int(0))
    end
  in {kind: "Call", callee:, arguments:}
    fail "todo Call"
  in {kind: "Var", text: name}
    fail "todo Var"
  in {kind: "Str", value: value}
     LLVM::ConstantArray.string(value)
  in {kind: "Int", value: value}
    fail "todo Int"
  in {kind: "Binary", lhs:, op:, rhs:}
    fail "todo Binary"
  in {kind: "If", condition:, then: then_, otherwise:}
    fail "nil builder while compiling if" if builder.nil?
    cond = compile_to_llvm
  else
    puts "unexpected node #{node}"
    return
  end

  # hello = mod.globals.add(LLVM::ConstantArray.string("Hello"), :hello) do |var|
  #   var.linkage = :private
  #   var.global_constant = true
  #   var.unnamed_addr = true
  #   var.initializer = LLVM::ConstantArray.string("Hello")
  # end

  # cputs = mod.functions.add("puts", [LLVM.Pointer(LLVM::Int8)], LLVM::Int32) do |function, string|
  #   function.add_attribute :no_unwind_attribute
  #   string.add_attribute :no_capture_attribute
  # end
  
  # main = mod.functions.add('main', [], LLVM::Int32) do |function|
  #   function.basic_blocks.append.build do |b|
  #     zero = LLVM.Int(0)
  #     cast210 = b.gep hello, [zero, zero], 'cast210'
  #     b.call cputs, cast210
  #     b.ret zero
  #   end
  # end

  # mod.dump

  # puts "--------------------"
  
  # LLVM.init_jit

  # engine = LLVM::JITCompiler.new(mod)
  # engine.run_function(main)
  # engine.dispose
end



case ARGV[0]
when "compile_to_ruby"
  print(compile_to_ruby(JSON.parse(STDIN.read, symbolize_names: true)[:expression]))
when "compile_to_python"
  print(compile_to_python(JSON.parse(STDIN.read, symbolize_names: true)[:expression]))
when "compile_to_llvm"
  mod = LLVM::Module.new('rinha')
  compile_to_llvm(JSON.parse(STDIN.read, symbolize_names: true)[:expression], mod)
  mod.dump
when "eval"
  eval_(JSON.parse(STDIN.read, symbolize_names: true)[:expression], {})
else
  fail "Usage: ruby rinha.rb {compile|eval} < input.json"
end
