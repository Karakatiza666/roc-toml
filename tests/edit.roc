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
			}

		Err(_) => "ERR"
	}

line : Str, List(Str) -> Try(U64, [NoEntry, Bad])
line = |text, path|
	match Toml.parse(text) {
		Ok(doc) => doc.line(path)
		Err(_) => Err(Bad)
	}

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
