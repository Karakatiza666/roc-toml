app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.7.0/HBigHQhVZWEF2EkLxpYK35u8P6UNsAmPYxpNFTxXK1Br.tar.zst",
	pkg: "../package/main.roc",
}

import fuzz.Fuzz
import pkg.Toml
import pkg.Value

## F-REMOVE, R-H1 and Q4: remove each root key that has a scalar value. The new
## table has all other keys. The text parses to it. The lines before the entry
## stay the same.
test : Str -> Fuzz.Outcome
test = |text|
	match Toml.parse(text) {
		Err(_) => Fuzz.keep
		Ok(doc) => {
			for (key, value) in doc.table().to_list() {
				if scalar(value) {
					check(doc, key)
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

check : Toml, Str -> {}
check = |doc, key|
	match (doc.remove([key]), doc.line([key])) {
		(Ok(edited), Ok(at)) => {
			if edited.table() != doc.table().remove(key) {
				crash "the table after remove is wrong for key ${key}"
			}
			match Toml.parse(edited.to_str()) {
				Ok(again) if again.table() == edited.table() => {}
				_ => crash "the text after remove does not parse to the new table"
			}
			before = at - 1
			if doc.to_str().split_on("\n").take_first(before) != edited.to_str().split_on("\n").take_first(before) {
				crash "a line before the entry changed"
			}
		}

		_ => crash "a root key with a scalar value has no entry: ${key}"
	}

target = Fuzz.target_with({
	examples: [],
	name: "remove-entry",
	generator: Fuzz.str,
	test,
	show: Str.inspect,
})
