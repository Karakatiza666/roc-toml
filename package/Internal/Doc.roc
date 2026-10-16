import /Value
import Grammar
import Tree

## A parse: the root table, and an index of the sections and entries with
## their byte positions, for the span edits.
Doc :: [].{

	## A range of bytes: `start` is the first byte, `end` is after the last.
	Span : { start : U64, end : U64 }

	## A section. Index 0 is the root table, before the first header.
	## `reach` is True when the path names a table through tables only, so
	## not into an array of tables.
	Sec : { path : List(Str), array : Bool, start : U64, end : U64, reach : Bool }

	## An entry `key = value`.
	##
	## | Field | Meaning |
	## | --- | --- |
	## | `path` | The full key path |
	## | `sec` | The index of its section |
	## | `keys` | The spans of the key parts that the entry writes |
	## | `value` | The span of the value |
	## | `place` | `Line` for an entry on its own line, `Inner` for an entry in an inline table |
	## | `inline` | `Yes` when the value is an inline table |
	Ent : {
		path : List(Str),
		sec : U64,
		keys : List(Span),
		value : Span,
		place : [Line, Inner({ at : U64, count : U64, prev_end : U64, next_start : U64, open : U64, close : U64 })],
		inline : [No, Yes({ count : U64, last_end : U64 })],
	}

	## The sections and entries in the order of the text. `bom` is the size
	## of the byte order mark (3 or 0).
	Index : { bom : U64, secs : List(Sec), ents : List(Ent) }

	## Parses the text. When `strict` is False, a date or time with a field
	## out of range is not an error (the edits use this to read their text).
	read : Str, Bool -> Try({ table : Dict(Str, Value), index : Index }, { line : U64, column : U64, message : Str })
	read = |text, strict| {
		bytes = text.to_utf8()
		match build(bytes, strict) {
			Ok(done) => Ok(done)
			Err({ offset, message }) => Err({ line: Doc.line_of(bytes, offset), column: column_of(bytes, offset), message })
		}
	}

	## The 1-based line of a byte offset.
	line_of : List(U8), U64 -> U64
	line_of = |bytes, offset| 1 + bytes.take_first(offset).count_if(|b| b == '\n')
}

Problem : { offset : U64, message : Str }

Pair : { keys : List({ name : Str, start : U64, end : U64 }), node : Grammar.Node }

column_of : List(U8), U64 -> U64
column_of = |bytes, offset|
	match bytes.take_first(offset).find_last_index(|b| b == '\n') {
		Ok(i) => offset - i
		Err(_) => offset + 1
	}

bom_size : List(U8) -> U64
bom_size = |bytes| if bytes.starts_with([0xEF, 0xBB, 0xBF]) 3 else 0

build : List(U8), Bool -> Try({ table : Dict(Str, Value), index : Doc.Index }, Problem)
build = |bytes, strict| {
	total = bytes.len()
	bom = bom_size(bytes)
	check_depth(bytes, bom)?
	items = Grammar.parse(bytes.drop_first(bom)) ? |e| { offset: bom + e.offset, message: e.message }
	var $tree = Tree.root
	var $section = []
	var $sid = 0
	var $secs = [{ path: [], array: Bool.False, start: bom, end: bom, reach: Bool.True }]
	var $ents = []
	for item in items {
		match item {
			Head(h) => {
				path = names(h.keys)
				$tree = Tree.header($tree, path, h.array) ? |m| { offset: total - h.start, message: m }
				$section = path
				$sid = $sid + 1
				$secs = $secs.append({ path, array: h.array, start: total - h.start, end: total - h.end, reach: Bool.False })
			}

			Pair(p) => {
				v = node_value(p.node, strict, total)?
				$tree = Tree.entry($tree, $section, names(p.keys), v, $sid) ? |m| { offset: key_start(p, total), message: m }
				$ents = $ents.concat(entries_of(p, $section, $sid, Line, total))
			}

			Blank => {}
		}
	}
	table =
		match Tree.to_value($tree) {
			Value.Table(d) => d
			_ => Dict.empty()
		}
	secs = $secs.map(|s| { path: s.path, array: s.array, start: s.start, end: s.end, reach: reaches(table, s.path) })
	Ok({ table, index: { bom, secs, ents: $ents } })
}

names : List({ name : Str, start : U64, end : U64 }) -> List(Str)
names = |keys| keys.map(|k| k.name)

key_start : Pair, U64 -> U64
key_start = |p, total|
	match p.keys.first() {
		Ok(k) => total - k.start
		Err(_) => total - p.node.start
	}

reaches : Dict(Str, Value), List(Str) -> Bool
reaches = |table, path|
	match path {
		[] => Bool.True
		[k, .. as rest] =>
			match table.get(k) {
				Ok(Value.Table(d)) => reaches(d, rest)
				_ => Bool.False
			}
	}

node_value : Grammar.Node, Bool, U64 -> Try(Value, Problem)
node_value = |node, strict, total|
	match node.form {
		Scalar(v) => Ok(v)
		Odd(v, m) => if strict Err({ offset: total - node.start, message: m }) else Ok(v)
		Arr(nodes) => nodes.map_try(|n| node_value(n, strict, total)).map_ok(|vs| Value.Array(vs))
		Inl(pairs) => inline_value(pairs, strict, total)
	}

inline_value : List(Pair), Bool, U64 -> Try(Value, Problem)
inline_value = |pairs, strict, total| {
	var $tree = Tree.root
	for p in pairs {
		v = node_value(p.node, strict, total)?
		$tree = Tree.entry($tree, [], names(p.keys), v, 0) ? |m| { offset: key_start(p, total), message: m }
	}
	Ok(Tree.to_value($tree))
}

# The entry of a pair, and the entries in its value when it is an inline table.
entries_of : Pair, List(Str), U64, [Line, Inner({ at : U64, count : U64, prev_end : U64, next_start : U64, open : U64, close : U64 })], U64 -> List(Doc.Ent)
entries_of = |p, prefix, sec, place, total| {
	path = prefix.concat(names(p.keys))
	span = |s, e| { start: total - s, end: total - e }
	value = span(p.node.start, p.node.end)
	match p.node.form {
		Inl(pairs) => {
			count = pairs.len()
			last_end = pairs.last().map_ok(|q| total - q.node.end) ?? value.start
			own = { path, sec, keys: p.keys.map(|k| span(k.start, k.end)), value, place, inline: Yes({ count, last_end }) }
			inner = pairs.map_with_index(
				|q, at| {
					prev_end = if at == 0 value.start + 1 else pairs.get(at - 1).map_ok(|r| total - r.node.end) ?? value.start
					next_start = pairs.get(at + 1).map_ok(|r| key_start(r, total)) ?? (value.end - 1)
					entries_of(q, path, sec, Inner({ at, count, prev_end, next_start, open: value.start + 1, close: value.end - 1 }), total)
				},
			)
			[own].concat(inner.join())
		}

		_ => [{ path, sec, keys: p.keys.map(|k| span(k.start, k.end)), value, place, inline: No }]
	}
}

# The most levels of arrays and inline tables in a value. The recursive
# parse uses the stack for each level: about 500 levels overflow the stack
# of a fuzz target, and "parse never crashes" (TESTING.md 4).
max_depth : U64
max_depth = 128

Scan : [Normal, Comment, Basic, Literal, MlBasic, MlLiteral]

# An error at the first `[` or `{` that is deeper than `max_depth`. Brackets
# in strings and comments do not count.
check_depth : List(U8), U64 -> Try({}, Problem)
check_depth = |bytes, start| {
	var $i = start
	var $depth = 0
	var $scan = Normal
	n = bytes.len()
	while $i < n {
		b = bytes.get($i) ?? 0
		step =
			match $scan {
				Normal => normal_step(bytes, $i, b)
				Comment => { next: if b == '\n' Normal else Comment, skip: 1, delta: Same }
				Basic => if b == '\\' { next: Basic, skip: 2, delta: Same } else { next: if b == '"' or b == '\n' Normal else Basic, skip: 1, delta: Same }
				Literal => { next: if b == '\'' or b == '\n' Normal else Literal, skip: 1, delta: Same }
				MlBasic => if b == '\\' { next: MlBasic, skip: 2, delta: Same } else if starts_at(bytes, $i, ['"', '"', '"']) { next: Normal, skip: 3, delta: Same } else { next: MlBasic, skip: 1, delta: Same }
				MlLiteral => if starts_at(bytes, $i, ['\'', '\'', '\'']) { next: Normal, skip: 3, delta: Same } else { next: MlLiteral, skip: 1, delta: Same }
			}
		match step.delta {
			Deeper => {
				$depth = $depth + 1
				if $depth > max_depth {
					return Err({ offset: $i, message: "the values are nested more than ${max_depth.to_str()} levels deep" })
				}
			}

			Shallower => {
				$depth = if $depth > 0 $depth - 1 else 0
			}

			Same => {}
		}
		$scan = step.next
		$i = $i + step.skip
	}
	Ok({})
}

normal_step : List(U8), U64, U8 -> { next : Scan, skip : U64, delta : [Deeper, Shallower, Same] }
normal_step = |bytes, i, b|
	match b {
		'#' => { next: Comment, skip: 1, delta: Same }
		'"' => if starts_at(bytes, i, ['"', '"', '"']) { next: MlBasic, skip: 3, delta: Same } else { next: Basic, skip: 1, delta: Same }
		'\'' => if starts_at(bytes, i, ['\'', '\'', '\'']) { next: MlLiteral, skip: 3, delta: Same } else { next: Literal, skip: 1, delta: Same }
		'[' | '{' => { next: Normal, skip: 1, delta: Deeper }
		']' | '}' => { next: Normal, skip: 1, delta: Shallower }
		_ => { next: Normal, skip: 1, delta: Same }
	}

starts_at : List(U8), U64, List(U8) -> Bool
starts_at = |bytes, i, prefix| bytes.sublist({ start: i, len: prefix.len() }) == prefix
