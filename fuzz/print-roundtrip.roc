app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.7.0/HBigHQhVZWEF2EkLxpYK35u8P6UNsAmPYxpNFTxXK1Br.tar.zst",
	pkg: "../package/main.roc",
}

import fuzz.Fuzz
import pkg.Toml

## F-ROUND, TESTING.md 4: for each text that parses, parse(print(table)) == table
target = Fuzz.target_with({
	examples: [],
	name: "print-roundtrip",
	generator: Fuzz.str,
	test: |text|
		match Toml.parse(text) {
			Err(_) => Fuzz.keep
			Ok(doc) =>
				match Toml.parse(Toml.print(doc.table())) {
					Ok(again) if again.table() == doc.table() => Fuzz.keep
					_ => crash "parse(print(table)) is not the table"
				}
		},
	show: Str.inspect,
})
