from typing import Any
import sys
import json
import operator as op


def eval_(node, env: dict[str, Any]):
    if type(node) is dict:
        kind = node["kind"]
        if kind == "Let":
            name = node["name"]["text"]
            env = env | {name: node["value"]}
            return eval_(node["next"], env)
        elif kind == "Function":
            pnames = map(op.itemgetter("text"), node["parameters"])
            return lambda *args: eval_(
                node["value"], env | {p: a for p, a in zip(pnames, args)}
            )
        elif kind == "Print":
            print(eval_(node["value"], env))
            return
        elif kind == "Call":
            callee = eval_(node["callee"], env)
            arguments = map(lambda arg: eval_(arg, env), node["arguments"])
            assert callable(callee), f"Not a function {callee}"
            return callee(*arguments)
        elif kind == "Var":
            return eval_(env[node["text"]], env)
        elif kind == "Int":
            return int(node["value"])
        elif kind == "Binary":
            lhs = eval_(node["lhs"], env)
            rhs = eval_(node["rhs"], env)
            op_mapping = {
                "Eq": op.eq,
                "Or": op.or_,
                "Sub": op.sub,
                "Add": op.add,
                "Lt": op.lt,
            }
            return op_mapping[node["op"]](lhs, rhs)
        elif kind == "If":
            if eval_(node["condition"], env):
                return eval_(node["then"], env)
            else:
                return eval_(node["otherwise"], env)
        else:
            raise RuntimeError(f"Unknown AST node {node}")
    elif callable(node):
        return node
    elif type(node) in (int, str, bool):
        return node
    else:
        raise RuntimeError(f"Unknown node {node}")
