app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.7.0/HBigHQhVZWEF2EkLxpYK35u8P6UNsAmPYxpNFTxXK1Br.tar.zst",
	pkg: "../package/main.roc",
}

import fuzz.Fuzz
import pkg.Toml

## F-TEXT, R-PK4 (span edit, as R-H1): a parsed document keeps its text, byte for byte
target = Fuzz.target_with({
	examples: [],
	name: "text-kept",
	generator: Fuzz.str,
	test: |text|
		match Toml.parse(text) {
			Err(_) => Fuzz.keep
			Ok(doc) => if (doc.to_str() == text) Fuzz.keep else crash "to_str is not the parsed text"
		},
	show: Str.inspect,
})
