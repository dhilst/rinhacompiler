require 'json'


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


case ARGV[0]
when "compile_to_ruby"
  print(compile_to_ruby(JSON.parse(STDIN.read, symbolize_names: true)[:expression]))
when "compile_to_python"
  print(compile_to_python(JSON.parse(STDIN.read, symbolize_names: true)[:expression]))

when "eval"
  eval_(JSON.parse(STDIN.read, symbolize_names: true)[:expression], {})
else
  fail "Usage: ruby rinha.rb {compile|eval} < input.json"
end
