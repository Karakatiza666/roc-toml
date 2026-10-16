# Changelog

## 0.2.0 (not released)

Planned asset: `H3F7MuifYcAb8FLdZ1ccrEikjYKr6BSpwtsvFz2kWztq.tar.zst` (`roc bundle` on `nightly-2026-10-14-38a3029`). The release workflow makes the real asset. Check that its name is the same.

This version changes the API. A `match` on the errors of `replace` or `insert` must have an `InvalidValue` branch.

| Change | Before (0.1.0) | Now |
| --- | --- | --- |
| `Toml.replace`, `Toml.insert` with a date or time that TOML text cannot have (year 10000, hour 99, `2023-02-30`, offset of 24 hours or more, nanosecond over 999999999), also in an array or inline table | A crash, or `Ok` with text that does not parse | `Err(InvalidValue)`. The document does not change. Path errors (`NoEntry`, `KeyExists`, `NotATable`) come first. |
| Column of a syntax error | Sometimes the start of the line (`a = ?` gave 1) | The first byte at which the text can no longer be the start of a valid TOML document (`a = ?` gives 5). At the end of the text: one past the last byte. |
| Column of a rule error (a key or table defined two times, an integer out of range, an impossible date) | The start of the line or of the value | The first byte of the value, or of the key part that is defined again |
| `Value.print`, `Toml.print` | | No change. The doc comments now say that a date or time that `parse` rejects is printed with its digits, and the output does not parse. |

## 0.1.0

First release: TOML 1.0.0 parse and print, and `replace`, `insert`, `remove`, `rename` and `line` that keep the comments, the order and the format.
