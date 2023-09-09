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

def indent(text, n)
  text.split("\n").map do |text|
    "#{' ' * n * 2}#{text}"
  end.join("\n")
end

def compile(node)
  case node
  in {kind: "Let", name: { text: function_name }, value: { kind: "Function", parameters:, value: body }, next: next_ }
    parameters = parameters.map {|x| x[:text]}.join(",")
    <<~EOS
    def #{function_name}(#{parameters})
    #{indent(compile(body), 1)}
    end

    #{compile(next_)}
    EOS
  in {kind: "Let", name: { text: }, value:, next: next_ }
    <<~EOS
    #{text} = #{compile(value)}
    #{compile(next_)}
    EOS
  in {kind: "Function", parameters:, value: body}
    pnames = parameters.map {|par| par[:text]}
    "->(#{pnames.join(',')}){ #{compile(body)} }"
  in {kind: "Print", value: }
    "puts(#{compile(value)})"
  in {kind: "Call", callee:, arguments:}
    callee = compile(callee)
    arguments = arguments.map {|arg| compile(arg) }.join(",")
    "#{callee}(#{arguments})"
  in {kind: "Var", text: name}
    name
  in {kind: "Int", value: value}
    value
  in {kind: "Binary", lhs:, op:, rhs:}
    lhs = compile(lhs)
    rhs = compile(rhs)
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
      if #{compile(condition)}
        #{compile(then_)}
      else
        #{compile(otherwise)}
      end
    EOS
  else
    fail "unexpected node #{node}"
  end
end

case ARGV[0]
when "compile_to_ruby"
  print(compile(JSON.parse(STDIN.read, symbolize_names: true)[:expression]))
when "eval"
  eval_(JSON.parse(STDIN.read, symbolize_names: true)[:expression], {})
else
  fail "Usage: ruby rinha.rb {compile|eval} < input.json"
end
