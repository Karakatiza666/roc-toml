import /Value

## A table while the parse builds it, with the facts that the TOML 1.0.0
## rules of definition need ("Table", "Array of Tables", "Keys").
##
## | Form | Made by |
## | --- | --- |
## | `Tab` `Implicit` | A header `[a.b]` makes `a` |
## | `Tab` `Header` | A header names it |
## | `Tab` `Dotted(n)` | A dotted key in section `n` makes it |
## | `Aot` | `[[a]]` headers, one element each |
## | `Leaf` | A value: it cannot change |
Tree := [
	Tab({ made : [Implicit, Header, Dotted(U64)], kids : Dict(Str, Tree) }),
	Aot(List(Tree)),
	Leaf(Value),
].{

	## The empty root table.
	root : Tree
	root = Tab({ made: Implicit, kids: Dict.empty() })

	## Adds a header `[keys]` (or `[[keys]]` when `array`). An error has the
	## index `at` of the key part that breaks a rule.
	header : Tree, List(Str), Bool -> Try(Tree, { at : U64, message : Str })
	header = |tree, keys, array| open(tree, keys, array, 0)

	## Adds `keys = value` in the section at `section`. `sid` is the number of
	## the section: a dotted key cannot add to a table made in another section.
	## An error has the index `at` in `keys` of the key part that breaks a rule.
	entry : Tree, List(Str), List(Str), Value, U64 -> Try(Tree, { at : U64, message : Str })
	entry = |tree, section, keys, value, sid| enter(tree, section, keys, value, sid)

	## The value of the tree.
	to_value : Tree -> Value
	to_value = |tree|
		match tree {
			Tab(t) => Value.Table(t.kids.map(|_k, kid| Tree.to_value(kid)))
			Aot(items) => Value.Array(items.map(Tree.to_value))
			Leaf(v) => v
		}
}

Problem : { at : U64, message : Str }

new_table : [Implicit, Header, Dotted(U64)] -> Tree
new_table = |made| Tab({ made, kids: Dict.empty() })

# A key with a value cannot be a table: the part before `at` names the value.
not_a_table : U64 -> Problem
not_a_table = |at| { at: if (at > 0) at - 1 else 0, message: "a key with a value cannot be a table" }

# `at` is the index of the first of `keys` in the key of the header.
open : Tree, List(Str), Bool, U64 -> Try(Tree, Problem)
open = |tree, keys, array, at|
	match tree {
		Tab(t) =>
			match keys {
				[] => Ok(tree)
				[k] => {
					kid = header_target(t.kids.get(k), array) ? |message| { at, message }
					Ok(Tab({ made: t.made, kids: t.kids.insert(k, kid) }))
				}

				[k, .. as rest] => {
					kid = t.kids.get(k) ?? new_table(Implicit)
					changed = open(kid, rest, array, at + 1)?
					Ok(Tab({ made: t.made, kids: t.kids.insert(k, changed) }))
				}
			}

		Aot(items) => in_last(items, |last| open(last, keys, array, at))
		Leaf(_) => Err(not_a_table(at))
	}

# The table that a header names, made or changed.
header_target : Try(Tree, [KeyNotFound]), Bool -> Try(Tree, Str)
header_target = |found, array|
	match (found, array) {
		(Err(_), Bool.False) => Ok(new_table(Header))
		(Err(_), Bool.True) => Ok(Aot([new_table(Header)]))
		(Ok(Tab({ made: Implicit, kids })), Bool.False) => Ok(Tab({ made: Header, kids }))
		(Ok(Aot(items)), Bool.True) => Ok(Aot(items.append(new_table(Header))))
		(Ok(Tab(_)), _) => Err("the table is defined twice")
		(Ok(Aot(_)), Bool.False) => Err("the name is an array of tables")
		(Ok(Leaf(_)), _) => Err("a key with a value cannot be a table")
	}

in_last : List(Tree), (Tree -> Try(Tree, Problem)) -> Try(Tree, Problem)
in_last = |items, change|
	match items.last() {
		Ok(last) => {
			changed = change(last)?
			Ok(Aot(items.drop_last(1).append(changed)))
		}

		Err(_) => Err({ at: 0, message: "an empty array of tables" })
	}

enter : Tree, List(Str), List(Str), Value, U64 -> Try(Tree, Problem)
enter = |tree, section, keys, value, sid|
	match (tree, section) {
		# The section of a `[[a]]` header is the last element.
		(Aot(items), _) => in_last(items, |last| enter(last, section, keys, value, sid))
		(_, []) => put(tree, keys, value, sid, 0)
		(Tab(t), [k, .. as rest]) => {
			kid = t.kids.get(k) ?? new_table(Implicit)
			changed = enter(kid, rest, keys, value, sid)?
			Ok(Tab({ made: t.made, kids: t.kids.insert(k, changed) }))
		}

		(Leaf(_), _) => Err({ at: 0, message: "a key with a value cannot be a table" })
	}

# `at` is the index of the first of `keys` in the key of the entry.
put : Tree, List(Str), Value, U64, U64 -> Try(Tree, Problem)
put = |tree, keys, value, sid, at|
	match tree {
		Tab(t) =>
			match keys {
				[] => Ok(tree)
				[k] =>
					if t.kids.contains(k) {
						Err({ at, message: "the key is defined twice" })
					} else {
						Ok(Tab({ made: t.made, kids: t.kids.insert(k, Leaf(value)) }))
					}

				[k, .. as rest] => {
					kid = dotted_target(t.kids.get(k), sid) ? |message| { at, message }
					changed = put(kid, rest, value, sid, at + 1)?
					Ok(Tab({ made: t.made, kids: t.kids.insert(k, changed) }))
				}
			}

		_ => Err(not_a_table(at))
	}

# The table that a part of a dotted key names, made or changed.
dotted_target : Try(Tree, [KeyNotFound]), U64 -> Try(Tree, Str)
dotted_target = |found, sid|
	match found {
		Err(_) => Ok(new_table(Dotted(sid)))
		Ok(Tab({ made: Implicit, kids })) => Ok(Tab({ made: Dotted(sid), kids }))
		Ok(Tab({ made: Dotted(n), kids })) if n == sid => Ok(Tab({ made: Dotted(n), kids }))
		Ok(Tab(_)) => Err("a dotted key cannot add to a table that is defined in another place")
		Ok(_) => Err("a key with a value cannot be a table")
	}
