import Value
import Internal/Doc as Doc
import Internal/Print as Print
import Internal/Edit as Edit

## A parsed TOML 1.0.0 document. It keeps the source text, so an edit
## (`replace`) changes only the bytes of one value and keeps all other bytes:
## comments, order, blank lines and the form of each value.
##
## An edit writes `Value.print` text. `replace` and `insert` give
## `InvalidValue`, and change nothing, when the new value has a date or time
## that `parse` would reject as TOML text: a year after 9999, a month out of
## 1 to 12, a day that the month does not have (with leap years), an hour
## over 23, a minute over 59, a second over 60, or an offset of 24 hours or
## more. A nanosecond over 999999999 is `InvalidValue` too: its text has
## more than 9 digits, and `parse` reads another value. The check also looks
## into arrays and inline tables.
Toml :: { text : Str, table : Dict(Str, Value), index : Doc.Index }.{

	## Parses TOML 1.0.0 text. Invalid text gives an error with a 1-based line
	## and column, and a message. The column counts bytes, and on line 1 also
	## the bytes of a byte order mark.
	##
	## | Error | Column |
	## | --- | --- |
	## | Syntax | The first byte at which the text can no longer be the start of a valid TOML document. At the end of the text: one past the last byte. |
	## | A rule: a key or a table defined two times, an integer out of the i64 range, a date or time out of range (also hour 24, minute 60, second 61, an offset of 24 hours) | The first byte of the key or the value that breaks the rule. For a dotted key, the first byte of the part that is defined again: `b` in `a.b`. |
	##
	## A value with more than 128 levels of arrays and inline tables is an
	## error too: the parse would use too much stack.
	parse : Str -> Try(Toml, [TomlErr({ line : U64, column : U64, message : Str })])
	parse = |text|
		match Doc.read(text) {
			Ok({ table: root, index }) => Ok({ text, table: root, index })
			Err(e) => Err(TomlErr(e))
		}

	## The root table of the document.
	table : Toml -> Dict(Str, Value)
	table = |doc| doc.table

	## The value at a key path. The path names keys only: it does not go into
	## an array, so it does not reach a table in an array of tables. The empty
	## path gives the root table.
	get : Toml, List(Str) -> Try(Value, [NotFound])
	get = |doc, path| lookup(Value.Table(doc.table), path)

	## A table as a TOML document. In each table, the keys whose values are not
	## tables and not arrays of tables come first, as `key = value` lines
	## (`Value.print`), in the order of the `Dict`. Then each sub-table is a
	## `[a.b]` section, and each array of tables (a non-empty array with only
	## tables in it) is one `[[a.b]]` section for each element. A table that is
	## not empty and has only sub-tables and arrays of tables gets no header
	## line. A blank line comes before each header line, except at the start.
	## Each line ends with `\n`. The empty table gives the empty text.
	##
	## The text parses back to an equal table when each date in it exists.
	## A date or time that `Toml.parse` would reject is printed with its
	## digits, and the output does not parse.
	print : Dict(Str, Value) -> Str
	print = |t| Print.document(t)

	## The text of the document. After `parse`, it is the parsed text.
	to_str : Toml -> Str
	to_str = |doc| doc.text

	## Replaces the value of the entry `key = value` at the key path. The new
	## text is the old text with the bytes of the old value replaced by the new
	## value text. All other bytes stay the same, also a comment on the same
	## line. The entry can be a dotted key or a key in an inline table.
	##
	## The new value text is `Value.print(new)`, except when the old value and
	## the new value are both strings. Then the new string keeps the kind of
	## the old one when it can:
	##
	## | Old kind | New text |
	## | --- | --- |
	## | `'...'` | `'...'` when the new string has no `'` and no control character other than tab, else a basic string |
	## | `"""..."""` | `"""..."""` with no newline after the opening quotes. A newline in the string is a raw `\n`, also in a file with `\r\n` line ends. Other characters as in `Value.print`. |
	## | `'''...'''` | `'''...'''` when the new string has no `'''` and no control character other than tab and newline, else as `"""..."""` |
	## | `"..."` | `Value.print(new)` |
	##
	## TOML trims a newline right after the opening quotes of a multi-line
	## string, so a new string that starts with a newline gets one more newline
	## there (`'''...'''` too).
	##
	## `NoEntry` when the path names no entry: a missing key, a table that a
	## header or a dotted key makes, a path into an array, or the empty path.
	## `InvalidValue` when the new value has a date or time that TOML cannot
	## write (see `Toml`). The `NoEntry` check comes first.
	replace : Toml, List(Str), Value -> Try(Toml, [NoEntry, InvalidValue])
	replace = |doc, path, new| Edit.replace(doc.text, doc.index, path, new).map_ok(reread)

	## The 1-based line of the first byte of the key of the entry at the key
	## path. `NoEntry` as for `replace`.
	line : Toml, List(Str) -> Try(U64, [NoEntry])
	line = |doc, path| Edit.line(doc.text, doc.index, path)

	## Adds the entry `key = value` (`Value.print(value)`, a bare key when it
	## can be) for the last key of the path, in the table that the rest of the
	## path names. All other bytes stay the same.
	##
	## | The table is | The new entry goes |
	## | --- | --- |
	## | A `[t]` section | On a new line after the last entry of the section, before the blank lines and comments that follow it. A section with no entry: after its header line. |
	## | The root table, with entries | As for a `[t]` section: after the last root entry |
	## | The root table, with no entry, and a header in the text | On a new line before the first header, after the comment lines and blank lines directly above that header, with a blank line between the new line and the header |
	## | The root table, with no entry and no header | At the end of the text |
	## | Made by dotted keys (`t.x = 1`) | On a new line `t.key = value` (the dotted form from the section) after the last line with that prefix |
	## | An inline table with entries | After the last value: `{ a = 1 }` becomes `{ a = 1, key = value }` |
	## | An empty inline table | `{}` becomes `{ key = value }` |
	## | Not in the text, under an inline table | A dotted key in the inline table: path `a.b.c` in `a = { x = 1 }` gives `{ x = 1, b.c = value }` |
	## | Not in the text, or only a parent of other tables | A new `[t]` header and the entry at the end of the text, with a blank line before the header. The empty text gives the text of `Toml.print`. |
	##
	## A new line ends with the newline of the first line end in the text (`\r\n`
	## or `\n`), else `\n`. When the last line has no newline, one comes first.
	##
	## `KeyExists` when the key is there (use `replace`), and for the empty
	## path (the root table is there). `NotATable` when the path goes through a
	## value that is not a table, or into an array of tables. `InvalidValue` as
	## for `replace`, after the other checks.
	insert : Toml, List(Str), Value -> Try(Toml, [KeyExists, NotATable, InvalidValue])
	insert = |doc, path, value| Edit.insert(doc.text, doc.table, doc.index, path, value).map_ok(reread)

	## Removes the entry at the key path. The lines of the entry go, with the
	## comment on its last line and its newline. Comment lines above the entry,
	## and a header of a table that becomes empty, stay. In an inline table,
	## the entry goes with the comma after it and the spaces after that comma,
	## or, for the last entry, from the comma before it. The only entry of an
	## inline table goes with the spaces around it: `{ a = 1 }` becomes `{}`.
	##
	## `NoEntry` as for `replace`.
	remove : Toml, List(Str) -> Try(Toml, [NoEntry])
	remove = |doc, path| Edit.remove(doc.text, doc.index, path).map_ok(reread)

	## Changes the last key of the entry at the key path. Only the bytes of that
	## key change: in `a.b = 1`, the `b`. The new key is bare when it can be.
	##
	## `NoEntry` as for `replace`. `KeyExists` when the table has the new key.
	rename : Toml, List(Str), Str -> Try(Toml, [NoEntry, KeyExists])
	rename = |doc, path, new_key| Edit.rename(doc.text, doc.table, doc.index, path, new_key).map_ok(reread)
}

lookup : Value, List(Str) -> Try(Value, [NotFound])
lookup = |value, path|
	match path {
		[] => Ok(value)
		[k, .. as rest] =>
			match value {
				Value.Table(t) =>
					match t.get(k) {
						Ok(kid) => lookup(kid, rest)
						Err(_) => Err(NotFound)
					}

				_ => Err(NotFound)
			}
	}

# The document of an edited text. The edits write only values that pass
# `Check.value_ok`, so the text parses.
reread : Str -> Toml
reread = |text|
	match Doc.read(text) {
		Ok({ table: root, index }) => { text, table: root, index }
		Err(e) => crash "roc-toml bug: the edited text does not parse (line ${e.line.to_str()}: ${e.message})"
	}
