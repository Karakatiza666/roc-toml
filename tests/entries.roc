app [main!] { pkg: "../package/main.roc" }

# Slice 5: insert, remove and rename of whole entries. R-H1 ("edits only
# string literals and whole entries ... keeps comments, order and
# formatting"), R-PK4, and the settled answers Q1 to Q5, Q7, Q11 and Q12 of the slice
# file (research/generic-packages/slices/roc-toml.md in the Talon repository).

import pkg.Toml
import pkg.Value

main! = |_args| Ok({})

int : I64 -> Value
int = |n| Value.Integer(n)

str : Str -> Value
str = |s| Value.String(s)

ins : Str, List(Str), Value -> Str
ins = |text, path, value|
	match Toml.parse(text) {
		Ok(doc) =>
			match doc.insert(path, value) {
				Ok(edited) => edited.to_str()
				Err(KeyExists) => "KeyExists"
				Err(NotATable) => "NotATable"
				Err(InvalidValue) => "InvalidValue"
			}

		Err(_) => "ERR"
	}

rem : Str, List(Str) -> Str
rem = |text, path|
	match Toml.parse(text) {
		Ok(doc) =>
			match doc.remove(path) {
				Ok(edited) => edited.to_str()
				Err(NoEntry) => "NoEntry"
			}

		Err(_) => "ERR"
	}

ren : Str, List(Str), Str -> Str
ren = |text, path, key|
	match Toml.parse(text) {
		Ok(doc) =>
			match doc.rename(path, key) {
				Ok(edited) => edited.to_str()
				Err(NoEntry) => "NoEntry"
				Err(KeyExists) => "KeyExists"
			}

		Err(_) => "ERR"
	}

# I-SEC1, Q1: after the last entry of the [t] section, before the blank lines and comments after it; the same-line comment stays
expect ins("[deps]\njson = \"^2.1\"   # pinned\n\n# next\n[other]\nx = 1\n", ["deps", "http"], str("^1")) == "[deps]\njson = \"^2.1\"   # pinned\nhttp = \"^1\"\n\n# next\n[other]\nx = 1\n"

# I-SEC2, Q1: a comment line between entries stays where it is
expect ins("[t]\na = 1\n# about b\nb = 2\n", ["t", "c"], int(3)) == "[t]\na = 1\n# about b\nb = 2\nc = 3\n"

# I-SEC3, Q1: a section with no entry gets the entry after its header line
expect ins("[t]\n\n[u]\n", ["t", "a"], int(1)) == "[t]\na = 1\n\n[u]\n"

# I-KEY1, Q1: the key is bare when it can be, else a basic string
expect ins("[t]\n", ["t", "a b"], int(1)) == "[t]\n\"a b\" = 1\n"

# I-EOF1, Q1, Q7: when the last line has no newline, one comes first
expect ins("[t]\na = 1", ["t", "b"], int(2)) == "[t]\na = 1\nb = 2\n"

# I-CRLF1, Q7: the new line ends with the newline of the first line end in the text
expect ins("[t]\r\na = 1\r\n", ["t", "b"], int(2)) == "[t]\r\na = 1\r\nb = 2\r\n"
expect ins("[t]\na = 1\r\n", ["t", "b"], int(2)) == "[t]\na = 1\r\nb = 2\n"

# I-DOT1, Q3: a table made by dotted keys gets a new dotted line after the last line with that prefix
expect ins("t.x = 1\nt.y = 2\nz = 3\n", ["t", "k"], int(4)) == "t.x = 1\nt.y = 2\nt.k = 4\nz = 3\n"
expect ins("[s]\nt.x = 1\n", ["s", "t", "k"], int(2)) == "[s]\nt.x = 1\nt.k = 2\n"

# I-INL1, Q3: an inline table with entries gets ", key = value" after its last value
expect ins("json = { path = \"x\" }  # p\n", ["json", "base"], str("b")) == "json = { path = \"x\", base = \"b\" }  # p\n"

# I-NEW1, Q2: a table that is not in the text gets a header at the end, with a blank line before it
expect ins("a = 1\n", ["deps", "x"], int(1)) == "a = 1\n\n[deps]\nx = 1\n"
expect ins("a = 1", ["t", "x"], int(1)) == "a = 1\n\n[t]\nx = 1\n"

# I-NEW2, Q2: a missing sub-table goes at the end, not after the section of its parent
expect ins("[a]\nx = 1\n\n[b]\ny = 2\n", ["a", "c", "z"], int(3)) == "[a]\nx = 1\n\n[b]\ny = 2\n\n[a.c]\nz = 3\n"

# I-NEW3, Q2 and Q3: a table that is only a parent of other tables gets its header at the end
expect ins("[t.sub]\nx = 1\n", ["t", "k"], int(1)) == "[t.sub]\nx = 1\n\n[t]\nk = 1\n"

# I-NEW4, Q2: the empty text (a new file) gives the text of Toml.print
expect ins("", ["deps", "x"], int(1)) == "[deps]\nx = 1\n"
expect ins("", ["x"], int(1)) == "x = 1\n"

# I-ROOT1, Q11: the root table with entries: after the last root entry, before the blank lines and comments after it
expect ins("a = 1  # c\n\n# probe\n[probe]\nslots = 12\n", ["b"], int(2)) == "a = 1  # c\nb = 2\n\n# probe\n[probe]\nslots = 12\n"
expect ins("a = 1\n", ["b"], int(2)) == "a = 1\nb = 2\n"

# I-ROOT2, Q11: the root table with no entry: before the first header, after the comment lines and blank lines above it, with a blank line before the header
expect ins("[probe]\nslots = 12\n", ["default"], str("x")) == "default = \"x\"\n\n[probe]\nslots = 12\n"
expect ins("# settings\n\n[probe]\nslots = 12\n", ["default"], str("x")) == "# settings\n\ndefault = \"x\"\n\n[probe]\nslots = 12\n"

# I-ROOT3, Q11: the root table with no entry and no header: at the end of the text
expect ins("# only a comment\n", ["a"], int(1)) == "# only a comment\na = 1\n"

# I-ROOT4, Q11 and Q7: the blank line before the header uses the newline of the text
expect ins("[probe]\r\nslots = 12\r\n", ["a"], int(1)) == "a = 1\r\n\r\n[probe]\r\nslots = 12\r\n"

# I-INL2, Q12: the empty inline table
expect ins("e = {}\n", ["e", "k"], int(1)) == "e = { k = 1 }\n"

# I-INL3, Q12: a missing table under an inline table is a dotted key in the inline table
expect ins("a = { x = 1 }\n", ["a", "b", "c"], int(2)) == "a = { x = 1, b.c = 2 }\n"

# I-VAL1, Q1: a table value is an inline table (Value.print)
expect ins("[t]\n", ["t", "p"], Value.Table(Dict.from_list([("path", str("x"))]))) == "[t]\np = { path = \"x\" }\n"

# I-ERR1, Q1: KeyExists when the key is there
expect ins("[t]\na = 1\n", ["t", "a"], int(2)) == "KeyExists"

# I-ERR2, Q3: NotATable for a path through a value that is not a table, or into an array of tables
expect ins("a = 1\n", ["a", "b"], int(2)) == "NotATable"
expect ins("[[p]]\nx = 1\n", ["p", "y"], int(2)) == "NotATable"

# I-GET1, Toml.insert: the document after the insert has the new value
expect
	match Toml.parse("[t]\na = 1\n") {
		Ok(doc) =>
			match doc.insert(["t", "b"], int(2)) {
				Ok(edited) => edited.get(["t", "b"]) == Ok(int(2)) and edited.get(["t", "a"]) == Ok(int(1))
				Err(_) => Bool.False
			}

		Err(_) => Bool.False
	}

# I-INV1, slice 6 (InvalidValue, as for replace): insert of a date that does not exist, in a section, in a new table, and nested
expect ins("[t]\n", ["t", "d"], Value.LocalDate({ year: 2023, month: 2, day: 30 })) == "InvalidValue"
expect ins("a = 1\n", ["new", "d"], Value.LocalTime({ hour: 24, minute: 0, second: 0, nanosecond: 0 })) == "InvalidValue"
expect ins("a = 1\n", ["b"], Value.Array([Value.Table(Dict.from_list([("y", Value.LocalDate({ year: 10000, month: 1, day: 1 }))]))])) == "InvalidValue"

# I-INV4, slice 6 Q17: insert of a nanosecond over 999999999
expect ins("[t]\n", ["t", "s"], Value.LocalTime({ hour: 1, minute: 2, second: 3, nanosecond: 1000000000 })) == "InvalidValue"

# I-INV2, slice 6: KeyExists and NotATable come before InvalidValue
expect ins("[t]\nd = 1\n", ["t", "d"], Value.LocalDate({ year: 2023, month: 2, day: 30 })) == "KeyExists"
expect ins("a = 1\n", ["a", "b"], Value.LocalDate({ year: 2023, month: 2, day: 30 })) == "NotATable"

# I-INV3, slice 6: a valid limit value is inserted as before
expect ins("[t]\n", ["t", "s"], Value.LocalTime({ hour: 23, minute: 59, second: 60, nanosecond: 0 })) == "[t]\ns = 23:59:60\n"

# DEL1, Q4: the line goes with its same-line comment and its newline
expect rem("[deps]\njson = \"^2.1\"  # pinned\nhttp = \"^1\"\n", ["deps", "json"]) == "[deps]\nhttp = \"^1\"\n"

# DEL2, Q4: a comment line above the entry stays
expect rem("# about a\na = 1\nb = 2\n", ["a"]) == "# about a\nb = 2\n"

# DEL3, Q4: the header of a table that becomes empty stays
expect rem("[t]\na = 1\n\n[u]\n", ["t", "a"]) == "[t]\n\n[u]\n"

# DEL4, Q4: all lines of a value over many lines go, with the comment on the last line
expect rem("m = [\n 1,\n 2,\n] # c\nx = 1\n", ["m"]) == "x = 1\n"

# DEL5, Q4: the last line with no newline
expect rem("a = 1\nb = 2", ["b"]) == "a = 1\n"

# DEL6, Q4: CRLF line ends and indentation of the other lines stay
expect rem("a = 1\r\nb = 2\r\n", ["a"]) == "b = 2\r\n"
expect rem("[t]\n  a = 1\n  b = 2\n", ["t", "a"]) == "[t]\n  b = 2\n"

# DEL7, Q4: an entry with a dotted key
expect rem("a.b = 1\na.c = 2\n", ["a", "b"]) == "a.c = 2\n"

# DEL8, Q4: in an inline table, the entry with the comma after it and the spaces after that comma
expect rem("j = { a = 1, b = 2 }\n", ["j", "a"]) == "j = { b = 2 }\n"

# DEL9, Q4: the last entry of an inline table goes from the comma before it
expect rem("j = { a = 1, b = 2 }\n", ["j", "b"]) == "j = { a = 1 }\n"

# DEL12, Q12: the only entry of an inline table goes with the spaces around it
expect rem("j = { a = 1 }\n", ["j", "a"]) == "j = {}\n"

# DEL13, Q4 and Q10: remove of the first entry keeps a BOM at the start
expect rem("\u(FEFF)a = 1\nb = 2\n", ["a"]) == "\u(FEFF)b = 2\n"

# DEL10, Toml.remove: NoEntry as for replace
expect rem("a = 1\n", ["b"]) == "NoEntry"
expect rem("[t]\na = 1\n", ["t"]) == "NoEntry"
expect rem("a = 1\n", []) == "NoEntry"

# DEL11, Toml.remove: the document after the remove has no key
expect
	match Toml.parse("a = 1\nb = 2\n") {
		Ok(doc) =>
			match doc.remove(["a"]) {
				Ok(edited) => edited.table() == Dict.from_list([("b", int(2))])
				Err(_) => Bool.False
			}

		Err(_) => Bool.False
	}

# REN1, Q5: only the bytes of the key change
expect ren("[deps]\njson = \"^2.1\"  # c\n", ["deps", "json"], "js") == "[deps]\njs = \"^2.1\"  # c\n"
expect ren("a   =   1\n", ["a"], "bb") == "bb   =   1\n"

# REN2, Q5: in a dotted key, only the last key changes
expect ren("a.b = 1\n", ["a", "b"], "c") == "a.c = 1\n"

# REN3, Q5: the new key is bare when it can be, else a basic string
expect ren("a = 1\n", ["a"], "a b") == "\"a b\" = 1\n"
expect ren("\"x y\" = 1\n", ["x y"], "xy") == "xy = 1\n"

# REN4, Q5: a key in an inline table
expect ren("j = { a = 1 }\n", ["j", "a"], "b") == "j = { b = 1 }\n"

# REN5, Q5: KeyExists when the table has the new key
expect ren("a = 1\nb = 2\n", ["a"], "b") == "KeyExists"

# REN6, Toml.rename: NoEntry as for replace
expect ren("a = 1\n", ["b"], "c") == "NoEntry"
expect ren("[t]\na = 1\n", ["t"], "u") == "NoEntry"

# REN7, Toml.rename: the document after the rename has the value under the new key
expect
	match Toml.parse("[t]\na = 1\n") {
		Ok(doc) =>
			match doc.rename(["t", "a"], "b") {
				Ok(edited) => edited.get(["t", "b"]) == Ok(int(1)) and edited.get(["t", "a"]) == Err(NotFound)
				Err(_) => Bool.False
			}

		Err(_) => Bool.False
	}
