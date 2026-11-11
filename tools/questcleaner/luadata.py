"""Reads the plain Lua table literals of a QuestieDB data file without running Lua."""
import re

TOKEN = re.compile(r"""
    \s+|--[^\n]*
  | (?P<num>-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)
  | (?P<str>"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')
  | (?P<name>[A-Za-z_]\w*)
  | (?P<sym>[{}\[\]=,;])
""", re.X | re.S)

ESC = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "'": "'"}


def _unquote(s):
    body, out, i = s[1:-1], [], 0
    while i < len(body):
        c = body[i]
        if c == "\\" and i + 1 < len(body):
            n = body[i + 1]
            if n.isdigit():
                m = re.match(r"\d{1,3}", body[i + 1:]).group()
                out.append(chr(int(m)))
                i += 1 + len(m)
                continue
            out.append(ESC.get(n, n))
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def tokens(text):
    pos = 0
    for m in TOKEN.finditer(text):
        if m.start() != pos:
            raise ValueError("unexpected text at %d: %r" % (pos, text[pos:pos + 40]))
        pos = m.end()
        kind = m.lastgroup
        if kind:
            yield kind, m.group(kind)
    if pos != len(text):
        raise ValueError("unexpected text at %d" % pos)


def parse(text):
    """A Lua table constructor -> dict (keys 1..n for positional values; nil holes skipped)."""
    toks = list(tokens(text))
    i = 0

    def value():
        nonlocal i
        kind, v = toks[i]
        i += 1
        if kind == "num":
            return float(v) if ("." in v or "e" in v.lower()) else int(v)
        if kind == "str":
            return _unquote(v)
        if kind == "name":
            if v == "nil":
                return None
            if v in ("true", "false"):
                return v == "true"
            raise ValueError("expression %s is not data" % v)
        if v == "{":
            t, n = {}, 0
            while toks[i][1] != "}":
                if toks[i][1] == "[":
                    i += 1
                    k = value()
                    assert toks[i][1] == "]"
                    i += 2  # ] =
                    t[k] = value()
                else:
                    n += 1
                    x = value()
                    if x is not None:
                        t[n] = x
                if toks[i][1] in (",", ";"):
                    i += 1
            i += 1
            return t
        raise ValueError("unexpected %r" % v)

    out = value()
    return out


def load(path, field):
    """The table in `QuestieDB.<field> = [[return {...}]]` of a QuestieDB data file."""
    src = open(path, encoding="utf-8").read()
    m = re.search(r"QuestieDB\.%s\s*=\s*\[(=*)\[\s*return\s*(.*?)\]\1\]" % field, src, re.S)
    if not m:
        raise ValueError("no %s in %s" % (field, path))
    return parse(m.group(2))
