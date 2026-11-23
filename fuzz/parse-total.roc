app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.7.0/HBigHQhVZWEF2EkLxpYK35u8P6UNsAmPYxpNFTxXK1Br.tar.zst",
	pkg: "../package/main.roc",
}

import fuzz.Fuzz
import pkg.Toml

## F-TOTAL, TESTING.md 4: parse never crashes. Each text gives Ok or Err.
target = Fuzz.target_with({
	examples: [],
	name: "parse-total",
	generator: Fuzz.str,
	test: |text|
		match Toml.parse(text) {
			Ok(_) => Fuzz.keep
			Err(_) => Fuzz.keep
		},
	show: Str.inspect,
})
