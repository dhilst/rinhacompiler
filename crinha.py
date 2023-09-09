import _crinha, json, sys


_crinha.eval_(json.load(sys.stdin)["expression"], {})
