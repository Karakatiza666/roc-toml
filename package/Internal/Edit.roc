import /Value
import Doc
import Print
import Text
import Check

## The span edits. Each edit gives the new text: the old text with the
## bytes of one span changed. The caller parses the new text again.
Edit :: [].{

	## The text with the value at `path` replaced.
	replace : Str, Doc.Index, List(Str), Value -> Try(Str, [NoEntry, InvalidValue])
	replace = |text, index, path, new| {
		e = find(index, path)?
		valid(new)?
		bytes = text.to_utf8()
		old = slice(bytes, e.value.start, e.value.end)
		Ok(splice(bytes, e.value.start, e.value.end, value_text(old, new)))
	}

	## The 1-based line of the first byte of the key of the entry at `path`.
	line : Str, Doc.Index, List(Str) -> Try(U64, [NoEntry])
	line = |text, index, path| {
		e = find(index, path)?
		Ok(Doc.line_of(text.to_utf8(), first_key(e)))
	}

	## The text with the last key of the entry at `path` changed.
	rename : Str, Dict(Str, Value), Doc.Index, List(Str), Str -> Try(Str, [NoEntry, KeyExists])
	rename = |text, table, index, path, new_key| {
		e = find(index, path)?
		if has_key(table, path.drop_last(1), new_key) {
			Err(KeyExists)
		} else {
			span = e.keys.last() ?? e.value
			Ok(splice(text.to_utf8(), span.start, span.end, Text.key(new_key)))
		}
	}

	## The text without the entry at `path`.
	remove : Str, Doc.Index, List(Str) -> Try(Str, [NoEntry])
	remove = |text, index, path| {
		e = find(index, path)?
		bytes = text.to_utf8()
		{ start, end } = removed_span(bytes, index.bom, e)
		Ok(splice(bytes, start, end, ""))
	}

	## The text with a new entry for the last key of `path`.
	insert : Str, Dict(Str, Value), Doc.Index, List(Str), Value -> Try(Str, [KeyExists, NotATable, InvalidValue])
	insert = |text, table, index, path, value|
		match path {
			# The empty path names the root table, and the root table is there.
			[] => Err(KeyExists)
			_ => {
				check_insert(table, path.drop_last(1), path.last() ?? "")?
				valid(value)?
				Ok(inserted(text.to_utf8(), table, index, path, value))
			}
		}
}

Ent : Doc.Ent

# The path checks come first, then this one (P6-2).
valid : Value -> Try({}, [InvalidValue])
valid = |value| if (Check.value_ok(value)) Ok({}) else Err(InvalidValue)

Span : Doc.Span

# --- Find ---

find : Doc.Index, List(Str) -> Try(Ent, [NoEntry])
find = |index, path|
	if path.is_empty() {
		Err(NoEntry)
	} else {
		index.ents.find_first(|e| e.path == path and reaches(index, e)).map_err(|_| NoEntry)
	}

reaches : Doc.Index, Ent -> Bool
reaches = |index, e| index.secs.get(e.sec).map_ok(|s| s.reach) ?? Bool.False

first_key : Ent -> U64
first_key = |e| e.keys.first().map_ok(|k| k.start) ?? e.value.start

has_key : Dict(Str, Value), List(Str), Str -> Bool
has_key = |table, path, key|
	match table_at(table, path) {
		Ok(t) => t.contains(key)
		Err(_) => Bool.False
	}

table_at : Dict(Str, Value), List(Str) -> Try(Dict(Str, Value), [Missing, NotATable])
table_at = |table, path|
	match path {
		[] => Ok(table)
		[k, .. as rest] =>
			match table.get(k) {
				Ok(Value.Table(t)) => table_at(t, rest)
				Ok(_) => Err(NotATable)
				Err(_) => Err(Missing)
			}
	}

# --- Bytes ---

slice : List(U8), U64, U64 -> List(U8)
slice = |bytes, start, end| bytes.sublist({ start, len: end - start })

# The bytes from `start` to `end` replaced by `new`. Each span edge is at an
# ASCII byte, so the result is valid UTF-8.
splice : List(U8), U64, U64, Str -> Str
splice = |bytes, start, end, new| Str.from_utf8_lossy(bytes.take_first(start).concat(new.to_utf8()).concat(bytes.drop_first(end)))

# The first byte of the line of `pos`, not before the byte order mark.
line_start : List(U8), U64, U64 -> U64
line_start = |bytes, pos, floor| {
	var $i = pos
	while $i > floor and bytes.get($i - 1) != Ok('\n') {
		$i = $i - 1
	}
	$i
}

# The byte after the line end that follows `pos`: the whitespace, the comment
# and the newline go with it. At the end of the text, the end of the text.
line_end : List(U8), U64 -> U64
line_end = |bytes, pos| {
	var $i = pos
	while bytes.get($i) == Ok(' ') or bytes.get($i) == Ok('\t') {
		$i = $i + 1
	}
	if bytes.get($i) == Ok('#') {
		while $i < bytes.len() and bytes.get($i) != Ok('\n') and bytes.get($i) != Ok('\r') {
			$i = $i + 1
		}
	}
	if bytes.get($i) == Ok('\r') and bytes.get($i + 1) == Ok('\n') {
		$i + 2
	} else if bytes.get($i) == Ok('\n') {
		$i + 1
	} else {
		$i
	}
}

# The newline of the first line end in the text, else `\n`.
newline_of : List(U8) -> Str
newline_of = |bytes|
	match bytes.find_first_index(|b| b == '\n') {
		Ok(i) if i > 0 and bytes.get(i - 1) == Ok('\r') => "\r\n"
		_ => "\n"
	}

ends_open : List(U8), U64 -> Bool
ends_open = |bytes, floor| bytes.len() > floor and bytes.last() != Ok('\n')

# --- Replace ---

Kind : [Basic, Literal, MlBasic, MlLiteral, NotString]

kind_of : List(U8) -> Kind
kind_of = |old|
	if old.starts_with(['\'', '\'', '\'']) {
		MlLiteral
	} else if old.starts_with(['\'']) {
		Literal
	} else if old.starts_with(['"', '"', '"']) {
		MlBasic
	} else if old.starts_with(['"']) {
		Basic
	} else {
		NotString
	}

# The text of the new value. A new string keeps the kind of an old string when it can.
value_text : List(U8), Value -> Str
value_text = |old, new|
	match new {
		Value.String(s) => string_text(kind_of(old), s)
		_ => Value.print(new)
	}

string_text : Kind, Str -> Str
string_text = |kind, s|
	match kind {
		Literal => if (fits_literal(s)) "'${s}'" else Text.basic(s)
		MlBasic => ml_basic(s)
		MlLiteral => if (fits_ml_literal(s)) "'''${lead(s)}${s}'''" else ml_basic(s)
		_ => Text.basic(s)
	}

ml_basic : Str -> Str
ml_basic = |s| "\"\"\"${lead(s)}${Text.ml_body(s)}\"\"\""

# TOML trims a newline right after the opening quotes, so a string that
# starts with a newline gets one more.
lead : Str -> Str
lead = |s| if (s.starts_with("\n")) "\n" else ""

fits_literal : Str -> Bool
fits_literal = |s| s.to_utf8().all(|b| b != '\'' and (b == '\t' or !Text.is_control(b)))

fits_ml_literal : Str -> Bool
fits_ml_literal = |s| !s.contains("'''") and s.to_utf8().all(|b| b == '\t' or b == '\n' or !Text.is_control(b))

# --- Remove ---

removed_span : List(U8), U64, Ent -> Span
removed_span = |bytes, bom, e|
	match e.place {
		Line => { start: line_start(bytes, first_key(e), bom), end: line_end(bytes, e.value.end) }
		Inner(i) =>
			if i.count == 1 {
				# The only entry goes with the spaces around it.
				{ start: i.open, end: i.close }
			} else if i.at + 1 < i.count {
				{ start: first_key(e), end: i.next_start }
			} else {
				{ start: i.prev_end, end: e.value.end }
			}
	}

# --- Insert ---

check_insert : Dict(Str, Value), List(Str), Str -> Try({}, [KeyExists, NotATable])
check_insert = |table, path, key|
	match table_at(table, path) {
		Ok(t) => if (t.contains(key)) Err(KeyExists) else Ok({})
		Err(NotATable) => Err(NotATable)
		Err(Missing) => Ok({})
	}

inserted : List(U8), Dict(Str, Value), Doc.Index, List(Str), Value -> Str
inserted = |bytes, table, index, path, value| {
	bom = index.bom
	parent = path.drop_last(1)
	key = path.last() ?? ""
	nl = newline_of(bytes)
	entry = "${Text.key(key)} = ${Value.print(value)}"
	if bytes.len() == bom {
		# A new file: the print of the table.
		Str.from_utf8_lossy(bytes).concat(Print.document(set_at(table, path, value)))
	} else {
		match inline_owner(index, parent) {
			Ok(owner) => in_inline(bytes, owner, parent, key, value)
			Err(_) =>
				if parent.is_empty() {
					in_root(bytes, index, entry, nl)
				} else {
					match section_of(index, parent) {
						Ok(s) => after_section(bytes, index, s, entry, nl)
						Err(_) =>
							match last_dotted(index, parent) {
								Ok({ e, base }) => after_line(bytes, bom, e.value.end, "${Text.path(parent.drop_first(base).append(key))} = ${Value.print(value)}", nl)
								Err(_) => at_new_header(bytes, bom, parent, entry, nl)
							}
					}
				}
		}
	}
}

set_at : Dict(Str, Value), List(Str), Value -> Dict(Str, Value)
set_at = |table, path, value|
	match path {
		[] => table
		[k] => table.insert(k, value)
		[k, .. as rest] => {
			kid =
				match table.get(k) {
					Ok(Value.Table(t)) => t
					_ => Dict.empty()
				}
			table.insert(k, Value.Table(set_at(kid, rest, value)))
		}
	}

# The entry whose value is the deepest inline table that holds the table at `parent`.
inline_owner : Doc.Index, List(Str) -> Try(Ent, [NotFound])
inline_owner = |index, parent| {
	owners = index.ents.keep_if(|e| is_inline(e) and !e.path.is_empty() and parent.starts_with(e.path) and reaches(index, e))
	owners.fold(
		Err(NotFound),
		|best, e|
			match best {
				Ok(b) if b.path.len() >= e.path.len() => best
				_ => Ok(e)
			},
	)
}

on_line : Ent -> Bool
on_line = |e|
	match e.place {
		Line => Bool.True
		Inner(_) => Bool.False
	}

is_inline : Ent -> Bool
is_inline = |e|
	match e.inline {
		Yes(_) => Bool.True
		No => Bool.False
	}

# In an inline table: `{}` becomes `{ key = value }`, else `, key = value` after the last value.
in_inline : List(U8), Ent, List(Str), Str, Value -> Str
in_inline = |bytes, owner, parent, key, value| {
	pair = "${Text.path(parent.drop_first(owner.path.len()).append(key))} = ${Value.print(value)}"
	match owner.inline {
		Yes({ count, last_end }) if count > 0 => splice(bytes, last_end, last_end, ", ${pair}")
		_ => splice(bytes, owner.value.start + 1, owner.value.end - 1, " ${pair} ")
	}
}

# The root table.
in_root : List(U8), Doc.Index, Str, Str -> Str
in_root = |bytes, index, entry, nl|
	match last_line_entry(index, 0) {
		Ok(e) => after_line(bytes, index.bom, e.value.end, entry, nl)
		Err(_) =>
			match index.secs.get(1) {
				Ok(first) => {
					at = line_start(bytes, first.start, index.bom)
					splice(bytes, at, at, "${entry}${nl}${nl}")
				}

				Err(_) => {
					gap = if (ends_open(bytes, index.bom)) nl else ""
					splice(bytes, bytes.len(), bytes.len(), "${gap}${entry}${nl}")
				}
			}
	}

# The `[t]` section of the table.
section_of : Doc.Index, List(Str) -> Try(U64, [NotFound])
section_of = |index, path| index.secs.find_first_index(|s| s.path == path and !s.array and s.reach)

after_section : List(U8), Doc.Index, U64, Str, Str -> Str
after_section = |bytes, index, s, entry, nl|
	match last_line_entry(index, s) {
		Ok(e) => after_line(bytes, index.bom, e.value.end, entry, nl)
		Err(_) => {
			header_end = index.secs.get(s).map_ok(|sec| sec.end) ?? bytes.len()
			after_line(bytes, index.bom, header_end, entry, nl)
		}
	}

last_line_entry : Doc.Index, U64 -> Try(Ent, [NotFound])
last_line_entry = |index, s| index.ents.keep_if(|e| e.sec == s and on_line(e)).last().map_err(|_| NotFound)

# The last line with a dotted key that makes the table at `parent`, and
# the length of the path of its section.
last_dotted : Doc.Index, List(Str) -> Try({ e : Ent, base : U64 }, [NotFound])
last_dotted = |index, parent| {
	found =
		index.ents.keep_if(
			|e| {
				base = index.secs.get(e.sec).map_ok(|s| s.path.len()) ?? parent.len()
				on_line(e) and base < parent.len() and e.path.len() > parent.len() and e.path.starts_with(parent)
			},
		)
	match found.last() {
		Ok(e) => Ok({ e, base: index.secs.get(e.sec).map_ok(|s| s.path.len()) ?? 0 })
		Err(_) => Err(NotFound)
	}
}

# A new line after the line of `pos`.
after_line : List(U8), U64, U64, Str, Str -> Str
after_line = |bytes, bom, pos, entry, nl| {
	at = line_end(bytes, pos)
	gap = if (at > bom and bytes.get(at - 1) != Ok('\n')) nl else ""
	splice(bytes, at, at, "${gap}${entry}${nl}")
}

# A new `[t]` header and the entry at the end of the text.
at_new_header : List(U8), U64, List(Str), Str, Str -> Str
at_new_header = |bytes, bom, parent, entry, nl| {
	gap = if (ends_open(bytes, bom)) "${nl}${nl}" else nl
	splice(bytes, bytes.len(), bytes.len(), "${gap}[${Text.path(parent)}]${nl}${entry}${nl}")
}
