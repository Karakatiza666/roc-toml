import /Value
import Text

## A table as a TOML document (the format of `Toml.print`).
Print :: [].{

	## The document text of a table.
	document : Dict(Str, Value) -> Str
	document = |table| {
		var $out = ""
		for section in sections([], table, Bool.False) {
			match section.header {
				Ok(h) => {
					gap = if ($out.is_empty()) "" else "\n"
					$out = "${$out}${gap}${h}\n"
				}

				Err(_) => {}
			}
			for l in section.lines {
				$out = "${$out}${l}\n"
			}
		}
		$out
	}
}

Section : { header : Try(Str, [None]), lines : List(Str) }

# The sections of the table at `path`: its own section first, then the
# sections of its sub-tables and arrays of tables. `element` is True for an
# element of an array of tables, which always gets a `[[path]]` header.
sections : List(Str), Dict(Str, Value), Bool -> List(Section)
sections = |path, table, element| {
	pairs = table.to_list()
	lines = pairs.keep_if(|(_, v)| !is_section(v)).map(|(k, v)| "${Text.key(k)} = ${Value.print(v)}")
	nested = pairs.keep_if(|(_, v)| is_section(v))
	header =
		if element {
			Ok("[[${Text.path(path)}]]")
		} else if path.is_empty() or (lines.is_empty() and !nested.is_empty()) {
			Err(None)
		} else {
			Ok("[${Text.path(path)}]")
		}
	own = { header, lines }
	rest = nested.map(|(k, v)| sub_sections(path.append(k), v)).join()
	[own].concat(rest)
}

sub_sections : List(Str), Value -> List(Section)
sub_sections = |path, value|
	match value {
		Value.Table(t) => sections(path, t, Bool.False)
		Value.Array(items) => items.map(|item| element_sections(path, item)).join()
		_ => []
	}

element_sections : List(Str), Value -> List(Section)
element_sections = |path, item|
	match item {
		Value.Table(t) => sections(path, t, Bool.True)
		_ => []
	}

# A table, or an array of tables: a non-empty array with only tables in it.
is_section : Value -> Bool
is_section = |value|
	match value {
		Value.Table(_) => Bool.True
		Value.Array(items) => !items.is_empty() and items.all(is_table)
		_ => Bool.False
	}

is_table : Value -> Bool
is_table = |value|
	match value {
		Value.Table(_) => Bool.True
		_ => Bool.False
	}
