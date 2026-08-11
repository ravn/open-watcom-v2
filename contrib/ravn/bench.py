#!/usr/bin/env python3
"""Oracle + baseline benchmark harness for CP/M-86 programs.

The genuine Digital Research C run-time is treated as the reference:

  * ORACLE (behaviour) -- the DR C build's console output is the source of
    truth.  A candidate build (e.g. Open Watcom C) is correct only if it
    reproduces that output.  Output lines that Dhrystone itself flags as
    "(implementation-dependent)" (the raw Ptr_Comp pointer value, which depends
    on memory layout) are masked before comparison; everything the benchmark
    self-checks must match exactly.

  * BASELINE (size + speed) -- the DR C build is 1.00x.  Size is the .CMD byte
    count; speed is the estimated iAPX 186 execution-clock total from running
    the program in cpm86run_unicorn (see cycles186.py for the model and its
    caveats -- it is a deterministic estimate, not cycle-exact hardware time).

Usage:
  bench.py compare ORACLE.CMD CANDIDATE.CMD [--args "A B"] [--stdin STR]
                   [--label-oracle DRC --label-candidate Watcom] [--raw]
  bench.py measure FILE.CMD [--args ...] [--stdin ...] [--json]
  bench.py baseline update NAME ORACLE.CMD [--args ...]   # write baseline.json
  bench.py baseline check  NAME CANDIDATE.CMD [--args ...] # vs stored baseline

A stored baseline.json lets the DR C numbers persist without the (copyright,
un-committable) DR C toolchain present.
"""
import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import cpm86run_unicorn as runner   # noqa: E402

BASELINE_JSON = os.path.join(HERE, "baseline.json")

# Lines Dhrystone documents as implementation-dependent (raw pointer value).
_IMPL_DEFINED = re.compile(r"(Ptr_Comp:\s*)\d+")


def normalize(text):
    """Mask output that is legitimately implementation-defined."""
    return _IMPL_DEFINED.sub(r"\g<1><impl-defined>", text)


def measure(cmd, args="", stdin=""):
    """Run a .CMD in Unicorn; return dict(output, size, insns, clocks)."""
    prog = os.path.splitext(os.path.basename(cmd))[0].upper()
    cmdline = " ".join([prog] + (args.split() if args else []))
    text, insns, clocks = runner.run(
        cmd, cmdline=cmdline, stdin_bytes=stdin.encode("cp437"),
        count_cycles=True)
    return {
        "output": text,
        "size": os.path.getsize(cmd),
        "insns": insns,
        "clocks": clocks,
    }


def _fmt(n):
    return format(n, ",d")


def _ms(clocks, mhz):
    return clocks / (mhz * 1000.0)   # clocks / (MHz*1e6) seconds -> *1e3 ms


def cmd_measure(a):
    m = measure(a.file, a.args, a.stdin)
    if a.json:
        print(json.dumps({k: v for k, v in m.items() if k != "output"}))
    else:
        sys.stdout.write(m["output"])
        print("\n-- %s --" % os.path.basename(a.file), file=sys.stderr)
        print("size   : %s bytes" % _fmt(m["size"]), file=sys.stderr)
        print("insns  : %s" % _fmt(m["insns"]), file=sys.stderr)
        print("clocks : ~%s  (estimated 80186)" % _fmt(m["clocks"]),
              file=sys.stderr)
        print("time   : ~%.1f ms  @ %.3g MHz  (estimate)"
              % (_ms(m["clocks"], a.mhz), a.mhz), file=sys.stderr)
    return 0


def cmd_compare(a):
    o = measure(a.oracle, a.args, a.stdin)
    c = measure(a.candidate, a.args, a.stdin)
    if a.raw:
        ok = o["output"] == c["output"]
    else:
        ok = normalize(o["output"]) == normalize(c["output"])

    lo, lc = a.label_oracle, a.label_candidate
    hdr = ("", "size (B)", "insns", "~80186 clocks", "~ms @%.3gMHz" % a.mhz)
    row = "%-14s %12s %14s %18s %14s"
    print(row % hdr)
    print(row % (lo + " (base)", _fmt(o["size"]), _fmt(o["insns"]),
                 _fmt(o["clocks"]), "%.1f" % _ms(o["clocks"], a.mhz)))
    print(row % (lc, _fmt(c["size"]), _fmt(c["insns"]),
                 _fmt(c["clocks"]), "%.1f" % _ms(c["clocks"], a.mhz)))
    rs = c["size"] / o["size"] if o["size"] else float("nan")
    ri = c["insns"] / o["insns"] if o["insns"] else float("nan")
    rc = c["clocks"] / o["clocks"] if o["clocks"] else float("nan")
    print(row % ("ratio", "%.2fx" % rs, "%.2fx" % ri, "%.2fx" % rc,
                 "%.2fx" % rc))
    print("(%s = 1.00x baseline; <1.00x means %s is smaller/faster)"
          % (lo, lc))

    print("\nbehaviour: %s" % (
        "MATCH \u2713 (candidate reproduces the DR C oracle output%s)" % (
            "" if a.raw else ", impl-defined pointer masked")
        if ok else "MISMATCH \u2717"))
    if not ok:
        import difflib
        on = o["output"] if a.raw else normalize(o["output"])
        cn = c["output"] if a.raw else normalize(c["output"])
        sys.stderr.writelines(difflib.unified_diff(
            on.splitlines(True), cn.splitlines(True),
            fromfile=lo, tofile=lc))
        return 1
    return 0


def cmd_baseline(a):
    store = {}
    if os.path.exists(BASELINE_JSON):
        store = json.load(open(BASELINE_JSON))
    if a.action == "update":
        m = measure(a.file, a.args, a.stdin)
        store[a.name] = {
            "args": a.args, "stdin": a.stdin,
            "size": m["size"], "insns": m["insns"], "clocks": m["clocks"],
            "output_normalized": normalize(m["output"]),
        }
        json.dump(store, open(BASELINE_JSON, "w"), indent=2, sort_keys=True)
        print("baseline[%s] = size %s, insns %s, ~%s clocks (DR C = 1.00x)"
              % (a.name, _fmt(m["size"]), _fmt(m["insns"]), _fmt(m["clocks"])))
        return 0
    # check
    if a.name not in store:
        print("no baseline named %r in %s" % (a.name, BASELINE_JSON),
              file=sys.stderr)
        return 2
    base = store[a.name]
    m = measure(a.file, a.args or base.get("args", ""),
                a.stdin or base.get("stdin", ""))
    ok = normalize(m["output"]) == base["output_normalized"]
    row = "%-12s %12s %14s %18s %14s"
    print(row % ("", "size", "insns", "~80186 clocks", "~ms @%.3gMHz" % a.mhz))
    print(row % ("DR C base", _fmt(base["size"]), _fmt(base["insns"]),
                 _fmt(base["clocks"]), "%.1f" % _ms(base["clocks"], a.mhz)))
    print(row % ("candidate", _fmt(m["size"]), _fmt(m["insns"]),
                 _fmt(m["clocks"]), "%.1f" % _ms(m["clocks"], a.mhz)))
    rc = m["clocks"] / base["clocks"]
    print(row % ("ratio", "%.2fx" % (m["size"] / base["size"]),
                 "%.2fx" % (m["insns"] / base["insns"]),
                 "%.2fx" % rc, "%.2fx" % rc))
    print("behaviour vs DR C oracle: %s"
          % ("MATCH \u2713" if ok else "MISMATCH \u2717"))
    return 0 if ok else 1


def build_parser():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    m = sub.add_parser("measure", help="run one .CMD and report size/insns/clocks")
    m.add_argument("file")
    m.add_argument("--args", default="")
    m.add_argument("--stdin", default="")
    m.add_argument("--mhz", type=float, default=6.0,
                   help="CPU clock for the ms estimate (default 6.0, RC759 80186)")
    m.add_argument("--json", action="store_true")
    m.set_defaults(func=cmd_measure)

    c = sub.add_parser("compare", help="DR C oracle .CMD vs candidate .CMD")
    c.add_argument("oracle")
    c.add_argument("candidate")
    c.add_argument("--args", default="")
    c.add_argument("--stdin", default="")
    c.add_argument("--mhz", type=float, default=6.0,
                   help="CPU clock for the ms estimate (default 6.0, RC759 80186)")
    c.add_argument("--label-oracle", default="DR C")
    c.add_argument("--label-candidate", default="Watcom")
    c.add_argument("--raw", action="store_true",
                   help="byte-exact compare (do not mask impl-defined output)")
    c.set_defaults(func=cmd_compare)

    b = sub.add_parser("baseline", help="store/check the DR C baseline.json")
    b.add_argument("action", choices=["update", "check"])
    b.add_argument("name")
    b.add_argument("file")
    b.add_argument("--args", default="")
    b.add_argument("--stdin", default="")
    b.add_argument("--mhz", type=float, default=6.0,
                   help="CPU clock for the ms estimate (default 6.0, RC759 80186)")
    b.set_defaults(func=cmd_baseline)
    return p


def main(argv=None):
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
