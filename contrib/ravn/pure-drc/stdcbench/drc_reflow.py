#!/usr/bin/env python3
# drc_reflow.py -- reflow over-long initializer lines onto short lines.
#
# WHY: DR C 1.11 (CP/M-86, 1984) silently truncates a source line once it
# exceeds an internal parse/token-buffer capacity.  When the truncated tail
# contains the closing '}' of an array initializer, the compiler emits a
# SPURIOUS "Error 61  Too many initializers.  Right brace } is missing." even
# though the initializer is brace-balanced and the element count is legal.
# Verified empirically on the real emulator (see FINDINGS.md): the identical
# token stream compiles cleanly once wrapped onto short lines.  The exact
# byte threshold depends on token width (3-digit numeric tokens trip it at
# ~1030+ char lines), so we wrap conservatively.
#
# Worked example (c90base-data.c / N01): the 417-element table
#     char c90base_data[] = {96,179,...,138,1};      (one ~1900-char line)
# fails Error 61; reflowed to <=16 values/line it compiles and links (N01.OBJ).
#
# Strategy: for any single physical line that is long AND contains a top-level
# '{...}' initializer, split the initializer body on TOP-LEVEL commas (comma at
# brace-depth 1 -- so nested {..} rows of a 2-D array stay intact) into chunks
# of <=16 elements, one chunk per line.  Everything else passes through byte
# for byte.
import sys, re

MAXLEN = 160   # only touch lines longer than this (short lines are already safe)
PERLINE = 16   # elements per wrapped line

def split_top(body):
    """Split on commas at brace-depth 1 (relative to the initializer body)."""
    out, buf, depth = [], [], 0
    for ch in body:
        if ch == '{':
            depth += 1; buf.append(ch)
        elif ch == '}':
            depth -= 1; buf.append(ch)
        elif ch == ',' and depth == 0:
            out.append(''.join(buf)); buf = []
        else:
            buf.append(ch)
    tail = ''.join(buf).strip()
    if tail != '':
        out.append(tail)
    return [t.strip() for t in out]

# head = up to and including the FIRST '{'; body = middle; tail = '};' (+ ws)
LINE = re.compile(r'^(.*?\{)(.*)(\}\s*;\s*)$')

for line in sys.stdin:
    nl = line.rstrip('\n')
    if len(nl) <= MAXLEN:
        sys.stdout.write(line); continue
    m = LINE.match(nl)
    if not m:
        sys.stdout.write(line); continue
    head, body, tail = m.group(1), m.group(2), m.group(3).strip()
    # brace-balance sanity: the body between the first '{' and final '}' must
    # be balanced (depth returns to 0) or we leave the line untouched.
    depth = 0; ok = True
    for ch in body:
        if ch == '{': depth += 1
        elif ch == '}':
            depth -= 1
            if depth < 0: ok = False; break
    if not ok or depth != 0:
        sys.stdout.write(line); continue
    toks = split_top(body)
    if len(toks) <= PERLINE:
        sys.stdout.write(line); continue
    sys.stdout.write(head + '\n')
    for i in range(0, len(toks), PERLINE):
        chunk = ','.join(toks[i:i+PERLINE])
        sys.stdout.write(chunk + (',' if i + PERLINE < len(toks) else '') + '\n')
    sys.stdout.write(tail + '\n')
