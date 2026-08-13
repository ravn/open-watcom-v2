#!/usr/bin/env python3
"""Convert C `enum` declarations to DR C 1.11-compatible `int` + inlined
integer constants.  DR C 1.11 has no enum keyword (verified: Error 89).

Reads preprocessed C on stdin, writes DR-C-friendly C on stdout.

Strategy (textual, good enough for stdcbench's single anonymous enum):
  1. Find each `[typedef] enum [tag] { body } [alias]` construct.
  2. Parse enumerators, assigning sequential values (honoring `= expr` when
     the expr is an integer literal; otherwise best-effort continue).
  3. Replace the construct:
       typedef enum {..} T;  -> typedef int T;
       enum tag {..} ;        -> (removed)
       enum {..}              -> int   (inline / variable position)
  4. Replace every whole-word enumerator name elsewhere with its int value.
"""
import re
import sys


def parse_enumerators(body):
    """body is the text between { and }.  Return list of (name, value)."""
    out = []
    val = 0
    # split on top-level commas (enum bodies have no nested braces/parens here)
    for item in body.split(','):
        item = item.strip()
        if not item:
            continue
        if '=' in item:
            name, expr = item.split('=', 1)
            name = name.strip()
            expr = expr.strip()
            try:
                val = int(expr, 0)
            except ValueError:
                # non-literal initializer: leave a marker, keep counting
                val = eval_const(expr, dict(out))
        else:
            name = item
        out.append((name, val))
        val += 1
    return out


def eval_const(expr, known):
    """Best-effort evaluate an enumerator initializer against prior names."""
    e = expr
    for nm, v in known.items():
        e = re.sub(r'\b' + re.escape(nm) + r'\b', str(v), e)
    try:
        return int(eval(e, {"__builtins__": {}}, {}))
    except Exception:
        return 0


def main():
    src = sys.stdin.read()
    consts = {}
    out = []
    i = 0
    n = len(src)
    # regex to find the start of an enum construct, optionally typedef-prefixed
    pat = re.compile(r'(typedef\s+)?enum\b(\s+[A-Za-z_]\w*)?\s*\{')
    while i < n:
        m = pat.search(src, i)
        if not m:
            out.append(src[i:])
            break
        out.append(src[i:m.start()])
        # find matching close brace
        brace = src.index('{', m.start())
        depth = 0
        j = brace
        while j < n:
            if src[j] == '{':
                depth += 1
            elif src[j] == '}':
                depth -= 1
                if depth == 0:
                    break
            j += 1
        body = src[brace + 1:j]
        for name, value in parse_enumerators(body):
            consts[name] = value
        is_typedef = m.group(1) is not None
        # after the closing brace: capture up to the terminating ';'
        k = j + 1
        semi = src.index(';', k)
        trailer = src[k:semi].strip()  # typedef alias name(s) or empty
        if is_typedef and trailer:
            out.append('typedef int ' + trailer + ';')
        elif is_typedef:
            out.append('typedef int ' + trailer + ';')
        elif trailer:
            # `enum tag {..} var;` -> `int var;`
            out.append('int ' + trailer + ';')
        else:
            # bare `enum tag {..};` tag definition -> drop entirely
            out.append('')
        i = semi + 1
    text = ''.join(out)
    # inline enumerator names -> integer values (whole word)
    if consts:
        names = sorted(consts, key=len, reverse=True)
        rx = re.compile(r'\b(' + '|'.join(re.escape(x) for x in names) + r')\b')
        text = rx.sub(lambda mm: str(consts[mm.group(1)]), text)
    sys.stdout.write(text)


if __name__ == '__main__':
    main()
