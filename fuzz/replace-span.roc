app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
	pkg: "../package/main.roc",
}

import fuzz.Fuzz
import pkg.Toml
import pkg.Value

Input := { text : Str, n : U64 }.{
	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(Input)
	generator_for = |_| { text: Fuzz.str, n: Fuzz.u64 }.Fuzz
}

## F-SPAN, R-PK4 and R-H1: replace the value of each root key that has a scalar value.
## The new table has the new value and all other values. The text parses to the
## new table. The lines before and after the entry stay the same.
test : Input -> Fuzz.Outcome
test = |input|
	match Toml.parse(input.text) {
		Err(_) => Fuzz.keep
		Ok(doc) => {
			new = Value.Integer(input.n.to_i64_wrap())
			for (key, old) in doc.table().to_list() {
				if scalar(old) {
					check(doc, key, new)
				}
			}
			Fuzz.keep
		}
	}

scalar : Value -> Bool
scalar = |value|
	match value {
		Value.Array(_) => Bool.False
		Value.Table(_) => Bool.False
		_ => Bool.True
	}

check : Toml, Str, Value -> {}
check = |doc, key, new|
	match (doc.replace([key], new), doc.line([key])) {
		(Ok(edited), Ok(at)) => {
			if edited.table() != doc.table().insert(key, new) {
				crash "the table after replace is wrong for key ${key}"
			}
			match Toml.parse(edited.to_str()) {
				Ok(again) if again.table() == edited.table() => {}
				_ => crash "the edited text does not parse to the edited table"
			}
			old_lines = doc.to_str().split_on("\n")
			new_lines = edited.to_str().split_on("\n")
			before = at - 1
			after = new_lines.len() - at
			if old_lines.take_first(before) != new_lines.take_first(before) {
				crash "a line before the entry changed"
			}
			if old_lines.take_last(after) != new_lines.take_last(after) {
				crash "a line after the entry changed"
			}
		}

		_ => crash "a root key with a scalar value has no entry: ${key}"
	}

target = Fuzz.target_with({
	name: "replace-span",
	generator: Input.generator_for(Default),
	test,
	show: |input| Str.inspect(input),
})
