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

eval_(JSON.parse(ARGF.read, symbolize_names: true)[:expression], {})
