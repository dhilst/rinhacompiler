from typing import Any
import sys
import json
from frozendict import frozendict
import operator as op
from dataclasses import dataclass
from functools import partial

dataclass = partial(dataclass, frozen=True)


class Node:
    pass


@dataclass
class Symbol(Node):
    name: str


def eval_(node, env: frozendict[str, Any]):
    match node:
        case {"kind": "Let", "name": name, "value": value, "next": next_}:
            name = name["text"]
            env = env | {name: value}
            return eval_(next_, env)
        case {"kind": "Function", "parameters": parameters, "value": value}:
            pnames = map(op.itemgetter("text"), parameters)
            return lambda *args: eval_(
                value, env | {p: a for p, a in dict(zip(pnames, args)).items()}
            )
        case {"kind": "Print", "value": value}:
            print(eval_(value, env))
            return
        case {"kind": "Call", "callee": callee, "arguments": arguments}:
            callee = eval_(callee, env)
            arguments = map(lambda arg: eval_(arg, env), arguments)
            assert callable(callee), f"Not a function {callee}"
            return callee(*arguments)
        case {"kind": "Var", "text": text}:
            return eval_(env[text], env)
        case {"kind": "Int", "value": value}:
            return int(value)
        case {"kind": "Binary", "lhs": lhs, "op": op_, "rhs": rhs}:
            lhs = eval_(lhs, env)
            rhs = eval_(rhs, env)
            op_mapping = {
                "Eq": op.eq,
                "Or": op.or_,
                "Sub": op.sub,
                "Add": op.add,
                "Lt": op.lt,
            }
            return op_mapping[op_](lhs, rhs)
        case {
            "kind": "If",
            "condition": condition,
            "then": then,
            "otherwise": otherwise,
        }:
            if eval_(condition, env):
                return eval_(then, env)
            else:
                return eval_(otherwise, env)
        case cb if callable(cb):
            return cb
        case x if type(x) in (int, str, bool):
            return x
        case _:
            raise RuntimeError(f"Unknown node {node}")


ast = json.load(sys.stdin)

print(eval_(ast["expression"], frozendict()))
