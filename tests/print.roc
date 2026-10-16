app [main!] { pkg: "../package/main.roc" }

# Slice 3: Value.print and Toml.print. The text forms are a proposal for the
# human review (TW24): TOML 1.0.0 lets a printer choose the form.

import pkg.Toml
import pkg.Value

main! = |_args| Ok({})

int : I64 -> Value
int = |n| Value.Integer(n)

str : Str -> Value
str = |s| Value.String(s)

t : List((Str, Value)) -> Value
t = |pairs| Value.Table(Dict.from_list(pairs))

doc : List((Str, Value)) -> Str
doc = |pairs| Toml.print(Dict.from_list(pairs))

date : U16, U8, U8 -> { year : U16, month : U8, day : U8 }
date = |year, month, day| { year, month, day }

time : U8, U8, U8, U32 -> { hour : U8, minute : U8, second : U8, nanosecond : U32 }
time = |hour, minute, second, nanosecond| { hour, minute, second, nanosecond }

round_trip : List((Str, Value)) -> Bool
round_trip = |pairs| {
	table = Dict.from_list(pairs)
	match Toml.parse(Toml.print(table)) {
		Ok(again) => again.table() == table
		Err(_) => Bool.False
	}
}

# P-STR1, Value.print (TOML 1.0.0 "String"): a basic string
expect Value.print(str("abc")) == "\"abc\""

# P-STR2, Value.print: a quote and a backslash get a backslash
expect Value.print(str("a\"b\\c")) == "\"a\\\"b\\\\c\""

# P-STR3, Value.print: the short escapes
expect Value.print(str("\u(8)\t\n\u(C)\r")) == "\"\\b\\t\\n\\f\\r\""

# P-STR4, Value.print: other control characters are \uXXXX
expect Value.print(str("\u(0)\u(1F)\u(7F)")) == "\"\\u0000\\u001F\\u007F\""

# P-STR5, Value.print: other characters stay as they are
expect Value.print(str("caf\u(E9) \u(1F600)")) == "\"caf\u(E9) \u(1F600)\""

# P-INT1, Value.print (TOML 1.0.0 "Integer"): decimal
expect Value.print(int(42)) == "42"
expect Value.print(int(-17)) == "-17"
expect Value.print(int(I64.lowest)) == "-9223372036854775808"

# P-FLT1, Value.print (TOML 1.0.0 "Float"): a float has a "." or an exponent
expect Value.print(Value.Float(1.0)) == "1.0"
expect Value.print(Value.Float(0.1)) == "0.1"
expect Value.print(Value.Float(-2.5)) == "-2.5"
expect Value.print(Value.Float(-0.0)) == "-0.0"
expect Value.print(Value.Float(1e300)) == "1e300"

# P-FLT2, Value.print: the special values
expect Value.print(Value.Float(F64.infinity)) == "inf"
expect Value.print(Value.Float(-F64.infinity)) == "-inf"
expect Value.print(Value.Float(F64.nan)) == "nan"

# P-BOOL1, Value.print (TOML 1.0.0 "Boolean")
expect Value.print(Value.Boolean(Bool.True)) == "true"
expect Value.print(Value.Boolean(Bool.False)) == "false"

# P-DT1, Value.print (TOML 1.0.0 "Offset Date-Time"): Z for offset 0, T between date and time
expect Value.print(Value.OffsetDateTime({ date: date(1979, 5, 27), time: time(7, 32, 0, 0), offset_minutes: 0 })) == "1979-05-27T07:32:00Z"
expect Value.print(Value.OffsetDateTime({ date: date(1979, 5, 27), time: time(0, 32, 0, 999999000), offset_minutes: -420 })) == "1979-05-27T00:32:00.999999-07:00"
expect Value.print(Value.OffsetDateTime({ date: date(1979, 5, 27), time: time(0, 32, 0, 0), offset_minutes: 345 })) == "1979-05-27T00:32:00+05:45"

# P-DT2, Value.print: local forms, 4-digit years, the fraction with no trailing zeros
expect Value.print(Value.LocalDateTime({ date: date(1979, 5, 27), time: time(7, 32, 0, 0) })) == "1979-05-27T07:32:00"
expect Value.print(Value.LocalDate(date(1, 1, 1))) == "0001-01-01"
expect Value.print(Value.LocalTime(time(7, 32, 0, 500000000))) == "07:32:00.5"
expect Value.print(Value.LocalTime(time(0, 0, 0, 1))) == "00:00:00.000000001"

# P-ARR1, Value.print (TOML 1.0.0 "Array")
expect Value.print(Value.Array([])) == "[]"
expect Value.print(Value.Array([int(1), str("a"), Value.Array([int(2)])])) == "[1, \"a\", [2]]"

# P-INL1, Value.print (TOML 1.0.0 "Inline Table"): keys in the order of the Dict
expect Value.print(t([])) == "{}"
expect Value.print(t([("a", int(1)), ("b", t([("c", str("x"))]))])) == "{ a = 1, b = { c = \"x\" } }"

# P-KEY1, Value.print (TOML 1.0.0 "Keys"): a bare key when it can be, else a basic string
expect Value.print(t([("bare_key-1", int(1))])) == "{ bare_key-1 = 1 }"
expect Value.print(t([("a.b", int(1))])) == "{ \"a.b\" = 1 }"
expect Value.print(t([("", int(1))])) == "{ \"\" = 1 }"
expect Value.print(t([("k\u(E9)y \"q\"", int(1))])) == "{ \"k\u(E9)y \\\"q\\\"\" = 1 }"

# P-DOC1, Toml.print: the empty table is the empty text
expect Toml.print(Dict.empty()) == ""

# P-DOC2, Toml.print: key/value lines, each with a newline
expect doc([("a", int(1)), ("b", str("x"))]) == "a = 1\nb = \"x\"\n"

# P-DOC3, Toml.print: values before sub-tables, a blank line before a header
expect doc([("t", t([("x", int(1))])), ("a", int(1))]) == "a = 1\n\n[t]\nx = 1\n"

# P-DOC4, Toml.print: a table with only sub-tables gets no header, and no blank line at the start
expect doc([("t", t([("u", t([("x", int(1))]))]))]) == "[t.u]\nx = 1\n"

# P-DOC5, Toml.print: an empty table gets a header
expect doc([("e", t([]))]) == "[e]\n"

# P-DOC6, Toml.print: an array of tables is one [[name]] section for each element
expect doc([("p", Value.Array([t([("n", str("a"))]), t([])]))]) == "[[p]]\nn = \"a\"\n\n[[p]]\n"

# P-DOC7, Toml.print: a sub-table of an element follows its [[name]] section
expect doc([("p", Value.Array([t([("n", str("a")), ("s", t([("x", int(1))]))])]))]) == "[[p]]\nn = \"a\"\n\n[p.s]\nx = 1\n"

# P-DOC8, Toml.print: an empty array, and an array with a value that is not a table, are inline
expect doc([("p", Value.Array([]))]) == "p = []\n"
expect doc([("p", Value.Array([t([("a", int(1))]), int(2)]))]) == "p = [{ a = 1 }, 2]\n"

# P-DOC9, Toml.print: a header key that is not bare is a basic string
expect doc([("a b", t([("x", int(1))]))]) == "[\"a b\"]\nx = 1\n"

# P-DOC10, Toml.print: an array of tables in a table that has only that array
expect doc([("t", t([("p", Value.Array([t([("x", int(1))])]))]))]) == "[[t.p]]\nx = 1\n"

# P-RT1, TESTING.md 4 (parse(print(doc)) == doc): special floats, odd keys, nested arrays of tables
expect round_trip([("f", Value.Array([Value.Float(F64.nan), Value.Float(-0.0), Value.Float(F64.infinity), Value.Float(5e-324)]))])
expect round_trip([("", t([("a.b", t([("\u(0)", str("\u(7F)\"\\"))]))]))])
expect round_trip([("p", Value.Array([t([("q", Value.Array([t([("r", int(1))]), t([])]))])]))])
expect round_trip([("i", int(I64.lowest)), ("j", int(I64.highest)), ("d", Value.LocalTime(time(23, 59, 59, 999999999)))])
