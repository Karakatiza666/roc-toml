#!/usr/bin/env python3
"""Writes the toml-test L0 apps from tests/fixtures/toml-test (see its SOURCE).

Usage: python3 -I scripts/gen-toml-test.py   (from the repository root)

Output (do not edit by hand):
  tests/toml_test_valid.roc      each valid case parses to the value in its .json
  tests/toml_test_invalid.roc    each invalid case gives an error
  tests/toml_test_roundtrip.roc  each valid case: parse(print(table)) == table
A case that is not valid UTF-8 cannot be a Str, so it is not written (the
caller of Toml.parse decodes the bytes). The script lists these cases.
"""
import json
import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIX = ROOT / "tests" / "fixtures" / "toml-test"
SOURCE_LINE = "toml-test v2.2.0 (ce08da1d), MIT, tests/fixtures/toml-test/SOURCE"


def roc_str(s):
    out = []
    for ch in s:
        c = ord(ch)
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "$":
            out.append("\\$")
        elif 0x20 <= c <= 0x7E:
            out.append(ch)
        else:
            out.append("\\u(%X)" % c)
    return '"' + "".join(out) + '"'


DT = re.compile(
    r"^(?:(\d{4})-(\d{2})-(\d{2}))?(?:[Tt ]?(\d{2}):(\d{2}):(\d{2})(?:\.(\d+))?)?([Zz]|[+-]\d{2}:\d{2})?$"
)


def nanos(frac):
    if not frac:
        return 0
    return int((frac + "000000000")[:9])


def offset(o):
    if o in ("Z", "z"):
        return 0
    sign = -1 if o[0] == "-" else 1
    return sign * (int(o[1:3]) * 60 + int(o[4:6]))


def roc_float(text):
    t = text.replace("_", "")
    if t in ("inf", "+inf"):
        return "F64.infinity"
    if t == "-inf":
        return "-F64.infinity"
    if t in ("nan", "+nan", "-nan"):
        return "F64.nan"
    f = float(t)
    if f == 0.0:
        return "-0.0" if math.copysign(1.0, f) < 0 else "0.0"
    r = repr(f).replace("e+", "e")
    return r


def tagged(o):
    t, v = o["type"], o["value"]
    if t == "string":
        return "Value.String(%s)" % roc_str(v)
    if t == "integer":
        n = int(v)
        if n == -(2**63):
            return "Value.Integer(I64.lowest)"
        return "Value.Integer(%d)" % n
    if t == "float":
        return "Value.Float(%s)" % roc_float(v)
    if t == "bool":
        return "Value.Boolean(Bool.%s)" % ("True" if v == "true" else "False")
    m = DT.match(v)
    if not m:
        raise ValueError("bad datetime " + v)
    y, mo, d, h, mi, s, frac, off = m.groups()
    if t == "datetime":
        return "odt(%d, %d, %d, %d, %d, %d, %d, %d)" % (
            int(y), int(mo), int(d), int(h), int(mi), int(s), nanos(frac), offset(off))
    if t == "datetime-local":
        return "ldt(%d, %d, %d, %d, %d, %d, %d)" % (
            int(y), int(mo), int(d), int(h), int(mi), int(s), nanos(frac))
    if t == "date-local":
        return "ld(%d, %d, %d)" % (int(y), int(mo), int(d))
    if t == "time-local":
        return "lt(%d, %d, %d, %d)" % (int(h), int(mi), int(s), nanos(frac))
    raise ValueError("bad type " + t)


def is_tagged(o):
    return (isinstance(o, dict) and set(o.keys()) == {"type", "value"}
            and isinstance(o["value"], str) and isinstance(o["type"], str))


def value(o):
    if is_tagged(o):
        return tagged(o)
    if isinstance(o, list):
        return "Value.Array([%s])" % ", ".join(value(x) for x in o)
    if isinstance(o, dict):
        return "Value.Table(%s)" % table(o)
    raise ValueError("bad json %r" % (o,))


def table(o):
    pairs = ", ".join("(%s, %s)" % (roc_str(k), value(v)) for k, v in o.items())
    return "Dict.from_list([%s])" % pairs


def ident(path, used):
    base = re.sub(r"[^a-z0-9]+", "_", path[: -len(".toml")].lower()).strip("_")
    name = "c_" + base
    n = name
    i = 2
    while n in used:
        n = "%s_%d" % (name, i)
        i += 1
    used.add(n)
    return n


HELPERS = '''
date : U16, U8, U8 -> { year : U16, month : U8, day : U8 }
date = |year, month, day| { year, month, day }

time : U8, U8, U8, U32 -> { hour : U8, minute : U8, second : U8, nanosecond : U32 }
time = |hour, minute, second, nanosecond| { hour, minute, second, nanosecond }

odt : U16, U8, U8, U8, U8, U8, U32, I16 -> Value
odt = |y, mo, d, h, mi, s, ns, off| Value.OffsetDateTime({ date: date(y, mo, d), time: time(h, mi, s, ns), offset_minutes: off })

ldt : U16, U8, U8, U8, U8, U8, U32 -> Value
ldt = |y, mo, d, h, mi, s, ns| Value.LocalDateTime({ date: date(y, mo, d), time: time(h, mi, s, ns) })

ld : U16, U8, U8 -> Value
ld = |y, mo, d| Value.LocalDate(date(y, mo, d))

lt : U8, U8, U8, U32 -> Value
lt = |h, mi, s, ns| Value.LocalTime(time(h, mi, s, ns))

parsed : Str -> Try(Dict(Str, Value), [Bad])
parsed = |text|
\tmatch Toml.parse(text) {
\t\tOk(doc) => Ok(doc.table())
\t\tErr(_) => Err(Bad)
\t}
'''

ROUNDTRIP = '''
round_trip : Str -> Bool
round_trip = |text|
\tmatch Toml.parse(text) {
\t\tOk(doc) =>
\t\t\tmatch Toml.parse(Toml.print(doc.table())) {
\t\t\t\tOk(again) => again.table() == doc.table()
\t\t\t\tErr(_) => Bool.False
\t\t\t}

\t\tErr(_) => Bool.False
\t}
'''


def header(title, imports_value):
    lines = [
        'app [main!] { pkg: "../package/main.roc" }',
        "",
        "# Generated by scripts/gen-toml-test.py. Do not edit.",
        "# %s" % title,
        "# Cases: %s" % SOURCE_LINE,
        "",
        "import pkg.Toml",
    ]
    if imports_value:
        lines.append("import pkg.Value")
    return lines


def main():
    files = [l.strip() for l in (FIX / "files-toml-1.0.0").read_text().splitlines() if l.strip()]
    tomls = [f for f in files if f.endswith(".toml")]
    skipped = []
    cases = []
    used = set()
    for f in tomls:
        raw = (FIX / f).read_bytes()
        try:
            raw.decode("utf-8")
        except UnicodeDecodeError:
            skipped.append(f)
            continue
        cases.append((f, ident(f, used)))

    def imports(sel):
        return ['import "fixtures/toml-test/%s" as %s : Str' % (f, n) for f, n in sel]

    valid = [(f, n) for f, n in cases if f.startswith("valid/")]
    invalid = [(f, n) for f, n in cases if f.startswith("invalid/")]

    out = header("Slices 1 and 2: each valid case parses to the value in its .json", True)
    out += imports(valid)
    out += ["", "main! = |_args| Ok({})"]
    out += HELPERS.rstrip("\n").split("\n")
    for f, n in valid:
        j = json.loads((FIX / f[: -len(".toml")]).with_suffix(".json").read_text())
        out += ["", "# TT-VALID, toml-test %s" % f, "expect parsed(%s) == Ok(%s)" % (n, table(j))]
    (ROOT / "tests" / "toml_test_valid.roc").write_text("\n".join(out) + "\n")

    out = header("Slices 1 and 2: each invalid case gives an error (TOML 1.0.0: invalid TOML must give an error)", False)
    out += imports(invalid)
    out += ["", "main! = |_args| Ok({})"]
    for f, n in invalid:
        out += ["", "# TT-INVALID, toml-test %s" % f, "expect Toml.parse(%s).is_err()" % n]
    (ROOT / "tests" / "toml_test_invalid.roc").write_text("\n".join(out) + "\n")

    out = header("Slice 3: parse(print(table)) == table for each valid case (TESTING.md 4)", False)
    out += imports(valid)
    out += ["", "main! = |_args| Ok({})"]
    out += ROUNDTRIP.rstrip("\n").split("\n")
    for f, n in valid:
        out += ["", "# TT-ROUND, toml-test %s" % f, "expect round_trip(%s)" % n]
    (ROOT / "tests" / "toml_test_roundtrip.roc").write_text("\n".join(out) + "\n")

    print("valid %d, invalid %d, not UTF-8 (not written) %d" % (len(valid), len(invalid), len(skipped)))
    for f in skipped:
        print("  not UTF-8: " + f)


if __name__ == "__main__":
    sys.exit(main())
