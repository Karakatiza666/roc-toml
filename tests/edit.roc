app [main!] { pkg: "../package/main.roc" }

# Slice 4: the span edit. R-PK4: a span edit that keeps comments, order and
# formatting, as R-H1 does for the header ("edits only string literals and
# whole entries ... a span-based edit, not a reprint").

import pkg.Toml
import pkg.Value

main! = |_args| Ok({})

int : I64 -> Value
int = |n| Value.Integer(n)

str : Str -> Value
str = |s| Value.String(s)

# The text after one replace, or "ERR" when parse or replace fails.
edit : Str, List(Str), Value -> Str
edit = |text, path, new|
	match Toml.parse(text) {
		Ok(doc) =>
			match doc.replace(path, new) {
				Ok(edited) => edited.to_str()
				Err(NoEntry) => "NoEntry"
				Err(InvalidValue) => "InvalidValue"
			}

		Err(_) => "ERR"
	}

line : Str, List(Str) -> Try(U64, [NoEntry, Bad])
line = |text, path|
	match Toml.parse(text) {
		Ok(doc) => doc.line(path)
		Err(_) => Err(Bad)
	}

date : U16, U8, U8 -> { year : U16, month : U8, day : U8 }
date = |year, month, day| { year, month, day }

time : U8, U8, U8 -> { hour : U8, minute : U8, second : U8, nanosecond : U32 }
time = |hour, minute, second| { hour, minute, second, nanosecond: 0 }

odt : I16 -> Value
odt = |offset_minutes| Value.OffsetDateTime({ date: date(2023, 1, 1), time: time(0, 0, 0), offset_minutes })

# A one-line document for the InvalidValue cases
dd : Str
dd = "d = 1979-05-27  # c\n"

# E-TXT1, R-H1 (keeps comments, order and formatting): to_str gives the parsed text, byte for byte
expect {
	text = "# top\r\n[b]   # tbl\r\n  z=1\r\n\r\n[a]\r\nx = 'lit'  \r\n"
	Toml.parse(text).map_ok(|d| d.to_str()) == Ok(text)
}

# E-REP1, R-H1: a new string value; the comment on the same line and all other bytes stay
expect edit("[deps]\njson = \"^2.1\"   # pinned\nhttp = \"^1\"\n", ["deps", "json"], str("^3")) == "[deps]\njson = \"^3\"   # pinned\nhttp = \"^1\"\n"

# E-BOM1, Q10 (settled): to_str keeps a byte order mark at the start
expect Toml.parse("\u(FEFF)a = 1\n").map_ok(|d| d.to_str()) == Ok("\u(FEFF)a = 1\n")

# E-KIND1, Q6 (settled): an old one-line literal string gives a literal string when the new string fits in one
expect edit("v = '^2.1'  # c\n", ["v"], str("^3")) == "v = '^3'  # c\n"
expect edit("v = 'a'\n", ["v"], str("C:\\x\ty")) == "v = 'C:\\x\ty'\n"

# E-KIND2, Q6: a new string with a quote ' or a newline is a basic string
expect edit("v = 'a'\n", ["v"], str("it's")) == "v = \"it's\"\n"
expect edit("v = 'a'\n", ["v"], str("a\nb")) == "v = \"a\\nb\"\n"

# E-KIND3, Q6: an old basic string stays a basic string, and a value that is not a string uses Value.print
expect edit("v = \"a\"\n", ["v"], str("C:\\x")) == "v = \"C:\\\\x\"\n"
expect edit("v = 'a'\n", ["v"], int(1)) == "v = 1\n"

# E-KIND4, Q13: an old multi-line basic string keeps its kind: no newline after the opening quotes, a raw newline, other characters as Value.print
expect edit("v = \"\"\"\nold\"\"\"\nw = 1\n", ["v"], str("say \"hi\"\nok")) == "v = \"\"\"say \\\"hi\\\"\nok\"\"\"\nw = 1\n"
expect edit("v = \"\"\"old\"\"\"\n", ["v"], str("x")) == "v = \"\"\"x\"\"\"\n"

# E-KIND5, Q13: an old multi-line literal string keeps its kind when the new string fits in it
expect edit("v = '''\nold'''\n", ["v"], str("C:\\x\nb")) == "v = '''C:\\x\nb'''\n"

# E-KIND6, Q13: else a multi-line basic string
expect edit("v = '''old'''\n", ["v"], str("a'''b")) == "v = \"\"\"a'''b\"\"\"\n"
expect edit("v = '''old'''\n", ["v"], str("a\u(1)b")) == "v = \"\"\"a\\u0001b\"\"\"\n"

# E-KIND7, Q13: a value that is not a string uses Value.print
expect edit("v = \"\"\"old\"\"\"\n", ["v"], int(1)) == "v = 1\n"

# E-REP2, Toml.replace: the document after the edit has the new value
expect
	match Toml.parse("[deps]\njson = \"^2.1\"\n") {
		Ok(doc) =>
			match doc.replace(["deps", "json"], str("^3")) {
				Ok(edited) => edited.get(["deps", "json"]) == Ok(str("^3"))
				Err(_) => Bool.False
			}

		Err(_) => Bool.False
	}

# E-REP3, R-H1: an entry with a dotted key
expect edit("a.b = 1 # c\n", ["a", "b"], int(2)) == "a.b = 2 # c\n"

# E-REP4, R-H1 (string literals): a key in an inline table; the other keys of the inline table stay
expect edit("json = { path = \"x\", base = \"old\" }\n", ["json", "base"], str("new")) == "json = { path = \"x\", base = \"new\" }\n"

# E-REP5, R-H1 (whole entries): the whole value of an entry, here an inline table
expect edit("json = { path = \"x\" }  # p\n", ["json"], Value.Table(Dict.from_list([("path", str("y"))]))) == "json = { path = \"y\" }  # p\n"

# E-REP6, R-H1: a value over many lines is one span; the lines after it stay
expect edit("m = [\n  \"a\", # first\n]\nx = 1\n", ["m"], Value.Array([str("b")])) == "m = [\"b\"]\nx = 1\n"

# E-REP7, Toml.replace: the new value can have another type
expect edit("a = 1\n", ["a"], str("one")) == "a = \"one\"\n"

# E-REP8, R-H1: a quoted key keeps its form
expect edit("\"a b\" = 1\n", ["a b"], int(2)) == "\"a b\" = 2\n"

# E-REP9, R-H1: CRLF line ends and the spaces around = stay
expect edit("a = 1\r\nb   =   2\r\n", ["b"], int(3)) == "a = 1\r\nb   =   3\r\n"

# E-REP10, R-H1: an entry in the root table of a file with headers and comments
expect edit("# head\nname = \"x\"\n\n[t]\nname = \"y\"\n", ["name"], str("z")) == "# head\nname = \"z\"\n\n[t]\nname = \"y\"\n"

# E-REP11, Toml.replace: two edits, one after the other
expect
	match Toml.parse("a = 1\nb = 2\n") {
		Ok(doc) =>
			match doc.replace(["a"], int(10)) {
				Ok(once) => once.replace(["b"], int(20)).map_ok(|d| d.to_str()) == Ok("a = 10\nb = 20\n")
				Err(_) => Bool.False
			}

		Err(_) => Bool.False
	}

# E-NO1, Toml.replace: NoEntry for a missing key
expect edit("a = 1\n", ["b"], int(2)) == "NoEntry"
expect edit("[t]\na = 1\n", ["t", "b"], int(2)) == "NoEntry"

# E-NO2, Toml.replace: NoEntry for a table that a header makes
expect edit("[deps]\na = 1\n", ["deps"], int(2)) == "NoEntry"

# E-NO3, Toml.replace: NoEntry for a table that a dotted key makes
expect edit("a.b = 1\n", ["a"], int(2)) == "NoEntry"

# E-NO4, Toml.replace: NoEntry for a path into an array of tables, and for the empty path
expect edit("[[p]]\nx = 1\n", ["p", "x"], int(2)) == "NoEntry"
expect edit("a = 1\n", [], int(2)) == "NoEntry"

# E-INV1, slice 6 (InvalidValue; TOML 1.0.0 dates are RFC 3339: a 4-digit year): a year after 9999
expect edit(dd, ["d"], Value.LocalDate(date(10000, 1, 1))) == "InvalidValue"
expect edit(dd, ["d"], Value.LocalDateTime({ date: date(65535, 1, 1), time: time(0, 0, 0) })) == "InvalidValue"

# E-INV2, slice 6 (RFC 3339 date-month, date-mday with leap years): a month or a day that does not exist
expect edit(dd, ["d"], Value.LocalDate(date(2023, 2, 30))) == "InvalidValue"
expect edit(dd, ["d"], Value.LocalDate(date(2100, 2, 29))) == "InvalidValue"
expect edit(dd, ["d"], Value.LocalDate(date(2023, 4, 31))) == "InvalidValue"
expect edit(dd, ["d"], Value.LocalDate(date(2023, 11, 31))) == "InvalidValue"
expect edit(dd, ["d"], Value.LocalDate(date(2023, 0, 10))) == "InvalidValue"
expect edit(dd, ["d"], Value.LocalDate(date(2023, 13, 10))) == "InvalidValue"
expect edit(dd, ["d"], Value.LocalDate(date(2023, 1, 0))) == "InvalidValue"

# E-INV3, slice 6 (RFC 3339 time-hour 00-23, time-minute 00-59, time-second 00-60): a time out of range
expect edit(dd, ["d"], Value.LocalTime(time(24, 0, 0))) == "InvalidValue"
expect edit(dd, ["d"], Value.LocalTime(time(99, 0, 0))) == "InvalidValue"
expect edit(dd, ["d"], Value.LocalTime(time(100, 0, 0))) == "InvalidValue"
expect edit(dd, ["d"], Value.LocalTime(time(12, 60, 0))) == "InvalidValue"
expect edit(dd, ["d"], Value.LocalTime(time(12, 0, 61))) == "InvalidValue"

# E-INV4, slice 6 (RFC 3339 time-numoffset: hour 00-23, minute 00-59): an offset of 24 hours or more
expect edit(dd, ["d"], odt(1440)) == "InvalidValue"
expect edit(dd, ["d"], odt(-1440)) == "InvalidValue"
expect edit(dd, ["d"], odt(6000)) == "InvalidValue"

# E-INV5, slice 6: the check looks into arrays and inline tables
expect edit(dd, ["d"], Value.Array([int(1), Value.LocalDate(date(2023, 2, 30))])) == "InvalidValue"
expect edit(dd, ["d"], Value.Table(Dict.from_list([("a", Value.Array([Value.LocalTime(time(24, 0, 0))]))]))) == "InvalidValue"

# E-INV6, slice 6: the limits themselves are valid, and the edit is as before
expect edit(dd, ["d"], Value.LocalDate(date(9999, 12, 31))) == "d = 9999-12-31  # c\n"
expect edit(dd, ["d"], Value.LocalDate(date(2024, 2, 29))) == "d = 2024-02-29  # c\n"
expect edit(dd, ["d"], Value.LocalDateTime({ date: date(0, 1, 1), time: time(23, 59, 60) })) == "d = 0000-01-01T23:59:60  # c\n"
expect edit(dd, ["d"], odt(1439)) == "d = 2023-01-01T00:00:00+23:59  # c\n"
expect edit(dd, ["d"], odt(-1439)) == "d = 2023-01-01T00:00:00-23:59  # c\n"

# E-INV8, slice 6 Q17: a nanosecond over 999999999 is InvalidValue; 999999999 is valid
expect edit(dd, ["d"], Value.LocalTime({ hour: 0, minute: 0, second: 0, nanosecond: 1000000000 })) == "InvalidValue"
expect edit(dd, ["d"], Value.OffsetDateTime({ date: date(2023, 1, 1), time: { hour: 0, minute: 0, second: 0, nanosecond: 4294967295 }, offset_minutes: 0 })) == "InvalidValue"
expect edit(dd, ["d"], Value.LocalTime({ hour: 0, minute: 0, second: 0, nanosecond: 999999999 })) == "d = 00:00:00.999999999  # c\n"

# E-INV7, slice 6: NoEntry comes before InvalidValue
expect edit(dd, ["x"], Value.LocalDate(date(2023, 2, 30))) == "NoEntry"

# E-LINE1, Toml.line: the line of the key of an entry
expect line("# c\n[deps]\njson = 1\n", ["deps", "json"]) == Ok(3)
expect line("\n\na.b = 1\n", ["a", "b"]) == Ok(3)
expect line("x = 1\njson = { path = \"x\" }\n", ["json", "path"]) == Ok(2)

# E-LINE4, Toml.line (R-TF4): the line of the key when the value has more than one line, and of the key after it
expect line("a = [\n  1,\n]\nb = 1\n", ["a"]) == Ok(1)
expect line("a = [\n  1,\n]\nb = 1\n", ["b"]) == Ok(4)
expect line("x = 0\ns = \"\"\"\none\ntwo\"\"\"\nc = 1\n", ["s"]) == Ok(2)
expect line("x = 0\ns = \"\"\"\none\ntwo\"\"\"\nc = 1\n", ["c"]) == Ok(5)

# E-LINE2, Toml.line: NoEntry as for replace
expect line("[deps]\n", ["deps"]) == Err(NoEntry)
expect line("a = 1\n", ["b"]) == Err(NoEntry)

# E-LINE3, Toml.line: the line after an edit that removes lines
expect
	match Toml.parse("m = [\n 1,\n 2,\n]\nx = 1\n") {
		Ok(doc) =>
			match doc.replace(["m"], Value.Array([])) {
				Ok(edited) => edited.line(["x"]) == Ok(2)
				Err(_) => Bool.False
			}

		Err(_) => Bool.False
	}
