# roc-toml

[TOML 1.0.0](https://toml.io/en/v1.0.0) parse and print for Roc, and edits that keep the comments, the order and the format of the file. Built on [roc-parser](https://github.com/lukewilliamboswell/roc-parser) 2.0.0.

| Function | Type | Result |
| --- | --- | --- |
| `Toml.parse` | `Str -> Try(Toml, [TomlErr({ line, column, message })])` | A document that keeps its text. Invalid TOML gives the line and column where the parser stopped. |
| `Toml.table`, `Toml.get` | `Toml -> Dict(Str, Value)`, `Toml, List(Str) -> Try(Value, [NotFound])` | The values. `get` takes a key path. |
| `Toml.print` | `Dict(Str, Value) -> Str` | New TOML text for a table. `parse(print(t))` gives `t` again. |
| `Toml.to_str` | `Toml -> Str` | The text of the document |
| `Toml.replace` | `Toml, List(Str), Value -> Try(Toml, [NoEntry])` | Changes one value. All other bytes stay the same. A string keeps its kind. |
| `Toml.insert`, `Toml.remove`, `Toml.rename` | | Add, remove or rename one entry. The text around it stays the same. |
| `Toml.line` | `Toml, List(Str) -> Try(U64, [NoEntry])` | The line of the key of an entry |
| `Value.print` | `Value -> Str` | The inline TOML form of one value |

`Value` is `[String(Str), Integer(I64), Float(F64), Boolean(Bool), OffsetDateTime, LocalDateTime, LocalDate, LocalTime, Array(List(Value)), Table(Dict(Str, Value))]`. Two NaN floats are equal.

| Rule | Behavior |
| --- | --- |
| Input | UTF-8 text. A BOM at the start is accepted and kept by `to_str`. |
| Times | Nanoseconds. Extra digits are cut. The offset is in minutes. Second 60 is accepted. |
| Nesting | More than 128 levels of arrays and inline tables is an error |
| New lines | An inserted line uses the line break of the first line end in the text (LF or CRLF), else LF. A multi-line string that an edit writes uses LF. |

## Usage

Add the release to the header of your app, package or platform:

```roc
toml: "https://github.com/Karakatiza666/roc-toml/releases/download/0.1.0/3icmtKz6XQUyHqu5JftcoJJT6a9YTND1B8z1UAmtqJpN.tar.zst",
```

Then:

```roc
import toml.Toml

text =
	\\# Settings
	\\[server]
	\\port = 8080 # the default
	\\

expect {
	doc = Toml.parse(text)?
	doc.get(["server", "port"]) == Ok(Integer(8080))
}

expect {
	doc = Toml.parse(text)?
	edited = doc.replace(["server", "port"], Integer(9090))?
	edited.to_str() == "# Settings\n[server]\nport = 9090 # the default\n"
}
```

## Tests

| Layer | Files | Tool |
| --- | --- | --- |
| L0 | `tests/*.roc`. Hand cases from the TOML 1.0.0 text, and the TOML 1.0.0 cases of [toml-test](https://github.com/toml-lang/toml-test) v2.2.0 (MIT license, in `tests/fixtures/toml-test/` with its `LICENSE` and `SOURCE`). `scripts/gen-toml-test.py` makes the 3 `tests/toml_test_*.roc` files. | `roc test` |
| L1 | `fuzz/*.roc` (properties: parse never crashes, print round trip, text kept, replace and remove change only their entry) | [roc-fuzz](https://github.com/lukewilliamboswell/roc-fuzz) 0.7.0 |

`scripts/test.sh [ROC [FUZZ_ROC]]` runs `roc check`, `roc fmt --check`, the L0 tests and the L1 targets. Use the nightly in `.roc-version`. CI (`.github/workflows/ci.yml`) runs the same checks on that nightly.

## Release

`.github/workflows/release.yml` makes a release with [roc-lang/release-package](https://github.com/roc-lang/release-package): `gh workflow run release.yml --ref main -f release_version=X.Y.Z`. The tag is `X.Y.Z` with no prefix, and the one package asset is `<hash>.tar.zst` from `roc bundle`.

## License

UPL-1.0, see `LICENSE`.
