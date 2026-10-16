app [main!] { pkg: "../package/main.roc" }

# Slice 2: keys, tables, arrays of tables, comments and Toml.get
# (TOML 1.0.0, https://toml.io/en/v1.0.0).

import pkg.Toml
import pkg.Value

main! = |_args| Ok({})

tbl : Str -> Try(Dict(Str, Value), [Bad])
tbl = |text|
	match Toml.parse(text) {
		Ok(doc) => Ok(doc.table())
		Err(_) => Err(Bad)
	}

bad : Str -> Bool
bad = |text| Toml.parse(text).is_err()

err_line : Str -> Try(U64, [NoError])
err_line = |text|
	match Toml.parse(text) {
		Err(TomlErr(e)) => Ok(e.line)
		Ok(_) => Err(NoError)
	}

err_pos : Str -> Try((U64, U64), [NoError])
err_pos = |text|
	match Toml.parse(text) {
		Err(TomlErr(e)) => Ok((e.line, e.column))
		Ok(_) => Err(NoError)
	}

get : Str, List(Str) -> Try(Value, [Bad])
get = |text, path|
	match Toml.parse(text) {
		Ok(doc) => doc.get(path).map_err(|_| Bad)
		Err(_) => Err(Bad)
	}

int : I64 -> Value
int = |n| Value.Integer(n)

str : Str -> Value
str = |s| Value.String(s)

t : List((Str, Value)) -> Value
t = |pairs| Value.Table(Dict.from_list(pairs))

# S-DOC1, TOML 1.0.0 "Spec": an empty document is an empty table
expect tbl("") == Ok(Dict.empty())

# S-DOC2, "Spec" and "Comment": whitespace, newlines and comments only
expect tbl("  \n# a comment\n\t\n") == Ok(Dict.empty())

# S-DOC3, "Spec": a newline is LF or CRLF
expect tbl("a = 1\r\nb = 2\r\n") == Ok(Dict.from_list([("a", int(1)), ("b", int(2))]))

# S-DOC4, "Spec": a bare CR is not a newline
expect bad("a = 1\rb = 2")

# S-DOC5, "Spec": the last line needs no newline
expect tbl("a = 1") == Ok(Dict.from_list([("a", int(1))]))

# S-BOM1, Q10 (settled): a byte order mark at the start is skipped
expect tbl("\u(FEFF)a = 1\n") == Ok(Dict.from_list([("a", int(1))]))

# S-BOM2, Q10: a byte order mark that is not at the start is not skipped
expect bad("a = 1\n\u(FEFF)b = 2")

# S-BOM3, Q10: U+FEFF in a string value is a character of the value
expect tbl("a = \"\u(FEFF)\"") == Ok(Dict.from_list([("a", str("\u(FEFF)"))]))

# S-COM1, TOML 1.0.0 "Comment": a comment after a value
expect tbl("key = \"value\" # This is a comment, until the end of the line\n") == Ok(Dict.from_list([("key", str("value"))]))

# S-COM2, "Comment": a control character other than tab is not allowed in a comment
expect bad("# a\u(1)b\n")

# S-KV1, TOML 1.0.0 "Key/Value Pair": whitespace around the key and the value is ignored
expect tbl("  key   =   \"value\"  ") == Ok(Dict.from_list([("key", str("value"))]))

# S-KV2, "Key/Value Pair": the key, the equals sign and the value are on one line
expect bad("key = # INVALID\n")
expect bad("key\n= 1")

# S-KV3, "Key/Value Pair": a newline or the end of the file must come after a key/value pair
expect bad("first = \"Tom\" last = \"Preston-Werner\"")

# S-KEY1, TOML 1.0.0 "Keys": bare keys with ASCII letters, digits, underscores and dashes
expect tbl("bare_key = 1\nbare-key = 2\n1234 = 3") == Ok(Dict.from_list([("bare_key", int(1)), ("bare-key", int(2)), ("1234", int(3))]))

# S-KEY2, "Keys": quoted keys, basic and literal
expect tbl("\"127.0.0.1\" = 1\n\"character encoding\" = 2\n'key2' = 3\n'quoted \"value\"' = 4") == Ok(Dict.from_list([("127.0.0.1", int(1)), ("character encoding", int(2)), ("key2", int(3)), ("quoted \"value\"", int(4))]))

# S-KEY3, "Keys": an empty bare key is an error, an empty quoted key is valid
expect bad("= \"no key name\"")
expect tbl("\"\" = \"blank\"") == Ok(Dict.from_list([("", str("blank"))]))
expect tbl("'' = 'blank'") == Ok(Dict.from_list([("", str("blank"))]))

# S-KEY4, "Keys": dotted keys make tables, whitespace around the dot is ignored
expect tbl("physical.color = \"orange\"\nsite.\"google.com\" = true\nfruit . flavor = \"banana\"") == Ok(Dict.from_list([("physical", t([("color", str("orange"))])), ("site", t([("google.com", Value.Boolean(Bool.True))])), ("fruit", t([("flavor", str("banana"))]))]))

# S-KEY5, "Keys": a key defined twice is an error
expect bad("name = \"Tom\"\nname = \"Pradyun\"")

# S-KEY6, "Keys": bare and quoted forms of one key are the same key
expect bad("spelling = \"favorite\"\n\"spelling\" = \"favourite\"")

# S-KEY7, "Keys": a key with a value cannot become a table
expect bad("fruit.apple = 1\nfruit.apple.smooth = true")

# S-KEY8, "Keys": dotted keys of one table can be in any order
expect tbl("apple.type = \"fruit\"\norange.type = \"fruit\"\napple.skin = \"thin\"") == Ok(Dict.from_list([("apple", t([("type", str("fruit")), ("skin", str("thin"))])), ("orange", t([("type", str("fruit"))]))]))

# S-KEY9, "Keys": a bare key that looks like a float is two keys
expect tbl("3.14159 = \"pi\"") == Ok(Dict.from_list([("3", t([("14159", str("pi"))]))]))

# S-KEY10, "Keys": a bare key has no other characters
expect bad("k\u(E9)y = 1")
expect bad("a b = 1")

# S-TBL1, TOML 1.0.0 "Table": a header and its key/value pairs, until the next header
expect tbl("[table-1]\nkey1 = \"some string\"\n[table-2]\nkey1 = \"another string\"") == Ok(Dict.from_list([("table-1", t([("key1", str("some string"))])), ("table-2", t([("key1", str("another string"))]))]))

# S-TBL2, "Table": dotted and quoted header names, whitespace around the parts
expect tbl("[dog.\"tater.man\"]\ntype.name = \"pug\"") == Ok(Dict.from_list([("dog", t([("tater.man", t([("type", t([("name", str("pug"))]))]))]))]))
expect tbl("[ j . \"\u(029E)\" . 'l' ]") == Ok(Dict.from_list([("j", t([("\u(029E)", t([("l", t([]))]))]))]))

# S-TBL3, "Table": the parent tables are made when needed
expect tbl("[x.y.z.w]") == Ok(Dict.from_list([("x", t([("y", t([("z", t([("w", t([]))]))]))]))]))

# S-TBL4, "Table": a table defined twice is an error
expect bad("[fruit]\napple = \"red\"\n[fruit]\norange = \"orange\"")
expect bad("[fruit]\napple = \"red\"\n[fruit.apple]\ntexture = \"smooth\"")

# S-TBL5, "Table": a super-table after its sub-table is valid
expect tbl("[x.y.z.w]\n[x]\na = 1") == Ok(Dict.from_list([("x", t([("a", int(1)), ("y", t([("z", t([("w", t([]))]))]))]))]))

# S-TBL6, "Table": the root table has the pairs before the first header
expect tbl("name = \"Fido\"\n[owner]\nname = \"Regina\"") == Ok(Dict.from_list([("name", str("Fido")), ("owner", t([("name", str("Regina"))]))]))

# S-TBL7, "Table": a table made by dotted keys cannot get a header
expect bad("[fruit]\napple.color = \"red\"\n[fruit.apple]")

# S-TBL8, "Table": a header can add a sub-table to a table made by dotted keys
expect tbl("[fruit]\napple.color = \"red\"\n[fruit.apple.texture]\nsmooth = true") == Ok(Dict.from_list([("fruit", t([("apple", t([("color", str("red")), ("texture", t([("smooth", Value.Boolean(Bool.True))]))]))]))]))

# S-TBL9, "Table": an empty header name is an error, and a header is on its own line
expect bad("[]")
expect bad("[a] b = 1")
expect bad("[a")

# S-INL1, TOML 1.0.0 "Inline Table": an inline table defines all its keys
expect bad("[product]\ntype = { name = \"Nail\" }\ntype.edible = false")

# S-INL2, "Inline Table": an inline table cannot add keys to a table that is already defined
expect bad("[product]\ntype.name = \"Nail\"\ntype = { edible = false }")

# S-INL3, "Inline Table": a header cannot extend an inline table
expect bad("a = { b = 1 }\n[a.c]")

# S-AOT1, TOML 1.0.0 "Array of Tables": each [[name]] header adds a table to the array
expect tbl("[[products]]\nname = \"Hammer\"\n[[products]]\n[[products]]\nname = \"Nail\"") == Ok(Dict.from_list([("products", Value.Array([t([("name", str("Hammer"))]), t([]), t([("name", str("Nail"))])]))]))

# S-AOT2, "Array of Tables": sub-tables and nested arrays go to the last element
expect tbl("[[fruits]]\nname = \"apple\"\n[fruits.physical]\ncolor = \"red\"\n[[fruits.varieties]]\nname = \"red delicious\"\n[[fruits.varieties]]\nname = \"granny smith\"\n[[fruits]]\nname = \"banana\"\n[[fruits.varieties]]\nname = \"plantain\"") == Ok(Dict.from_list([("fruits", Value.Array([t([("name", str("apple")), ("physical", t([("color", str("red"))])), ("varieties", Value.Array([t([("name", str("red delicious"))]), t([("name", str("granny smith"))])]))]), t([("name", str("banana")), ("varieties", Value.Array([t([("name", str("plantain"))])]))])]))]))

# S-AOT3, "Array of Tables": a sub-table before its parent element is an error
expect bad("[fruit.physical]\ncolor = \"red\"\n[[fruit]]\nname = \"apple\"")

# S-AOT4, "Array of Tables": a static array cannot be extended
expect bad("fruits = []\n[[fruits]]")

# S-AOT5, "Array of Tables": a normal table with the name of an array of tables is an error, and the reverse
expect bad("[[fruits]]\nname = \"apple\"\n[fruits]\ncolor = \"red\"")
expect bad("[fruits]\ncolor = \"red\"\n[[fruits]]\nname = \"apple\"")

# S-ERR1, Toml.parse: the error gives the line of a duplicate key (the second definition)
expect err_line("a = 1\nb = 2\na = 3\n") == Ok(3)

# S-ERR2, Toml.parse: the error gives the line of a bad value
expect err_line("[t]\nx = 1\ny = 01\n") == Ok(3)

# S-ERR3, Toml.parse: the error gives the line of an unterminated string
expect err_line("a = 1\nb = \"abc") == Ok(2)

# S-ERR4, slice 6 (error column, syntax): 1-based, in bytes. `v = 01` can still start `v = 01:02:03`, so the error is one past the last byte
expect err_pos("v = 01") == Ok((1, 7))
expect err_pos("[t]\nx = 1\ny = 01\n") == Ok((3, 7))
expect err_pos("a = 1\n  b = ?") == Ok((2, 7))

# S-ERR5, slice 6 and Q10: on line 1 the column counts the 3 bytes of a BOM
expect err_pos("\u(FEFF)v = 01") == Ok((1, 10))
expect err_pos("\u(FEFF)a = ?") == Ok((1, 8))
expect err_pos("\u(FEFF)a = 1\nb = ?") == Ok((2, 5))

# S-COL1, slice 6 (syntax): a bad byte in a value is the first byte that no valid document can have there
expect err_pos("a = ?") == Ok((1, 5))
expect err_pos("x = trux") == Ok((1, 8))
expect err_pos("x = .7") == Ok((1, 5))
expect err_pos("x = 1.\n") == Ok((1, 7))
expect err_pos("a = \"x\u(1)\"") == Ok((1, 7))
expect err_pos("a = [\n  1,\n  ?\n]") == Ok((3, 3))
expect err_pos("a = { x = 1,\n y = 2 }") == Ok((1, 13))

# S-COL2, slice 6 (syntax): a value that can still grow ends at the end of the text, one past the last byte
expect err_pos("v = 012") == Ok((1, 8))

# S-COL3, slice 6 (syntax): a bad byte in a key
expect err_pos("a b = 1") == Ok((1, 3))
expect err_pos("k\u(E9)y = 1") == Ok((1, 2))

# S-COL4, slice 6 (syntax): a bad byte in a table header
expect err_pos("[a b]") == Ok((1, 4))
expect err_pos("[a]x") == Ok((1, 4))
expect err_pos("[]") == Ok((1, 2))

# S-COL5, slice 6 (syntax): an unclosed string or array at the end of the text is one past the last byte
expect err_pos("a = \"abc") == Ok((1, 9))
expect err_pos("a = 1\nb = \"abc") == Ok((2, 9))
expect err_pos("a = \"\"\"abc") == Ok((1, 11))
expect err_pos("a = [1, 2") == Ok((1, 10))
expect err_pos("a = [1,\n") == Ok((2, 1))

# S-COL6, slice 6 (syntax): a missing newline after a value; a bare CR can still start CRLF, so the byte after it is the error
expect err_pos("a = 1 b = 2") == Ok((1, 7))
expect err_pos("a = 1\rb = 2") == Ok((1, 7))

# S-COL7, slice 6 (syntax): a control character in a comment
expect err_pos("# a\u(1)b") == Ok((1, 4))

# S-COL8, slice 6 (rule): a key or a table defined two times: the first byte of the second key
expect err_pos("a = 1\nb = 2\na = 3\n") == Ok((3, 1))
expect err_pos("a = 1\n  a = 2") == Ok((2, 3))
expect err_pos("[t]\nx = 1\n[t]") == Ok((3, 2))

# S-COL9, slice 6 (rule): an integer out of the i64 range: the first byte of the value
expect err_pos("n = 9223372036854775808") == Ok((1, 5))
expect err_pos("n = -9223372036854775809") == Ok((1, 5))

# S-COL10, slice 6 (rule): a date that does not exist: the first byte of the value, also in an array
expect err_pos("d = 2023-02-30") == Ok((1, 5))
expect err_pos("d = 2023-04-31T00:00:00Z") == Ok((1, 5))
expect err_pos("a = [1, 2023-02-30]") == Ok((1, 9))

# S-COL11, slice 6 Q18 (rule): a dotted key defined two times: the first byte of the part that is defined again
expect err_pos("a.b = 1\na.b = 2") == Ok((2, 3))
expect err_pos("x.y.z = 1\nx.y.z = 2") == Ok((2, 5))
expect err_pos("[a.b]\n[a.b]") == Ok((2, 4))
expect err_pos("t = { a.b = 1, a.b = 2 }") == Ok((1, 18))

# S-COL12, slice 6 Q19 (rule): hour 24, minute 60, second 61, an offset of 24 hours: the first byte of the value
expect err_pos("t = 24:00:00") == Ok((1, 5))
expect err_pos("t = 12:60:00") == Ok((1, 5))
expect err_pos("t = 12:00:61") == Ok((1, 5))
expect err_pos("d = 1979-05-27T07:32:00+24:00") == Ok((1, 5))
expect err_pos("a = [1, 24:00:00]") == Ok((1, 9))

# S-COL13, slice 6 C2 (syntax): a bad hex digit in a \u or \U escape is at the bad digit
expect err_pos("a = \"\\u12G4\"") == Ok((1, 10))
expect err_pos("a = \"\\U0001F6x0\"") == Ok((1, 14))
expect err_pos("a = 1\nb = \"\\u00ZZ\"") == Ok((2, 10))

# S-COL14, slice 6 C2 (code agent proposal, human to confirm): a surrogate or a code point over U+10FFFF is at the first hex digit
expect err_pos("a = \"\\uD800\"") == Ok((1, 8))
expect err_pos("a = \"\\U00110000\"") == Ok((1, 8))

# S-COL15, slice 6 C2 (rule) and RFC 3339 date-mday: November has 30 days, so the column is the start of the value
expect err_pos("d = 2023-11-31") == Ok((1, 5))

# S-GET1, Toml.get: a key path into nested tables
expect get("[a.b]\nc = 1", ["a", "b", "c"]) == Ok(int(1))
expect get("x = { y = \"z\" }", ["x", "y"]) == Ok(str("z"))

# S-GET2, Toml.get: a path to a table gives the table
expect get("[a]\nb = 1", ["a"]) == Ok(t([("b", int(1))]))

# S-GET3, Toml.get: the empty path gives the root table
expect get("b = 1", []) == Ok(t([("b", int(1))]))

# S-GET4, Toml.get: a missing key, or a path through a value that is not a table
expect get("a = 1", ["b"]) == Err(Bad)
expect get("a = 1", ["a", "b"]) == Err(Bad)

# S-GET5, Toml.get: a path does not go into an array of tables
expect get("[[a]]\nb = 1", ["a", "b"]) == Err(Bad)

# S-USE1, R-PK4 (a config file with comments, a table of string values, an inline table and an array)
expect {
	text =
		\\# settings
		\\name = "demo"   # the name
		\\
		\\[deps]
		\\json = "^2.1"
		\\http = "owner/http@^1"   # added by hand
		\\
		\\[patch]
		\\json = { path = "./patches/json/main.roc", base = "4W8SHzvwet9h" }
		\\
		\\[group]
		\\members = ["apps/*/main.roc", "examples/*.roc"]
		\\limits = { max = 100, slots = 12 }
	tbl(text) == Ok(Dict.from_list([("name", str("demo")), ("deps", t([("json", str("^2.1")), ("http", str("owner/http@^1"))])), ("patch", t([("json", t([("path", str("./patches/json/main.roc")), ("base", str("4W8SHzvwet9h"))]))])), ("group", t([("members", Value.Array([str("apps/*/main.roc"), str("examples/*.roc")])), ("limits", t([("max", int(100)), ("slots", int(12))]))]))]))
}

# S-DEEP1, nesting limit (proposal of the code agent, human to confirm): 128 nested arrays parse
expect tbl("v = ${"[".repeat(128)}${"]".repeat(128)}").is_ok()

# S-DEEP2, nesting limit: 129 nested arrays give an error, so parse never crashes on deep input (TESTING.md 4)
expect bad("v = ${"[".repeat(129)}${"]".repeat(129)}")

# S-DEEP3, nesting limit: 129 nested inline tables give an error
expect bad("v = ${"{ a = ".repeat(129)}1${" }".repeat(129)}")

# S-DEEP4, nesting limit: brackets in a string or in a comment do not count
expect tbl("v = \"${"[".repeat(200)}\"\n# ${"[".repeat(200)}\n") == Ok(Dict.from_list([("v", str("[".repeat(200)))]))

# S-BOM4, TOML 1.0.0 "Comment" (Q10 is a BOM outside strings and comments): U+FEFF in a comment is valid
expect tbl("# a\u(FEFF)b\nx = 1") == Ok(Dict.from_list([("x", int(1))]))
