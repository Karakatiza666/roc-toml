app [target] {
	fuzz: platform "https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.4.3/41NK5FShyGC9Z8HNpUdUeXMWwLmLNfFxsfmLvdPL4Fxb.tar.zst",
	pkg: "../package/main.roc",
}

import fuzz.Fuzz
import pkg.Toml
import pkg.Value

Input := { a : U64, b : U64, c : U64 }.{
	generator_for : Fuzz.FuzzEncoding -> Fuzz.Generator(Input)
	generator_for = |_| { a: Fuzz.u64, b: Fuzz.u64, c: Fuzz.u64 }.Fuzz
}

Date : { year : U16, month : U8, day : U8 }

Time : { hour : U8, minute : U8, second : U8, nanosecond : U32 }

## F-DATE, slice 6 (InvalidValue): replace and insert of a random date or time,
## some of them out of range. A valid value gives Ok as before (the new value,
## and a text that parses to the new table). An invalid value gives
## InvalidValue. Never a crash.
test : Input -> Fuzz.Outcome
test = |input| {
	{ value, valid } = make(input)
	match Toml.parse(bases.get((input.a // 80) % bases.len()) ?? "") {
		Ok(doc) => {
			check_replace(doc, value, valid)
			check_insert(doc, value, valid)
			Fuzz.keep
		}

		Err(_) => crash "the base text does not parse"
	}
}

# Base texts: each has an entry d and a table t
bases : List(Str)
bases = ["d = 1979-05-27  # c\n[t]\nx = 1\n", "d = 'x'\r\n\r\n[t]\r\n", "t.x = 1\nd = [1, 2]\n"]

nanos : List(U32)
nanos = [0, 0, 1, 500000000, 999999999, 1000000000, 4294967295]

years : List(U16)
years = [0, 1, 1979, 2000, 2023, 2024, 2100, 9999, 10000, 65535]

make : Input -> { value : Value, valid : Bool }
make = |{ a, b, c }| {
	date = { year: years.get((a // 8) % years.len()) ?? 0, month: (b % 14).to_u8_wrap(), day: ((b // 14) % 33).to_u8_wrap() }
	time = { hour: ((b // 462) % 26).to_u8_wrap(), minute: (c % 62).to_u8_wrap(), second: ((c // 62) % 63).to_u8_wrap(), nanosecond: nanos.get((a // 240) % nanos.len()) ?? 0 }
	offset = ((c // 3906) % 3000).to_i16_wrap() - 1500
	match a % 6 {
		0 => { value: Value.LocalDate(date), valid: date_ok(date) }
		1 => { value: Value.LocalTime(time), valid: time_ok(time) }
		2 => { value: Value.LocalDateTime({ date, time }), valid: date_ok(date) and time_ok(time) }
		3 => { value: Value.OffsetDateTime({ date, time, offset_minutes: offset }), valid: date_ok(date) and time_ok(time) and offset_ok(offset) }
		4 => { value: Value.Array([Value.Integer(1), Value.LocalDate(date)]), valid: date_ok(date) }
		_ => { value: Value.Table(Dict.from_list([("x", Value.Array([Value.LocalTime(time)]))])), valid: time_ok(time) }
	}
}

# The oracle: the RFC 3339 ranges of TOML 1.0.0, written here from the rule
date_ok : Date -> Bool
date_ok = |{ year, month, day }| {
	leap = (year % 4 == 0 and year % 100 != 0) or year % 400 == 0
	last =
		match month {
			2 => if leap 29 else 28
			4 | 6 | 9 | 11 => 30
			_ => 31
		}
	year <= 9999 and month >= 1 and month <= 12 and day >= 1 and day <= last
}

time_ok : Time -> Bool
time_ok = |{ hour, minute, second, nanosecond }| hour <= 23 and minute <= 59 and second <= 60 and nanosecond <= 999999999

offset_ok : I16 -> Bool
offset_ok = |minutes| minutes >= -1439 and minutes <= 1439

check_replace : Toml, Value, Bool -> {}
check_replace = |doc, value, valid|
	match doc.replace(["d"], value) {
		Ok(edited) if valid => same(edited, doc.table().insert("d", value))
		Ok(_) => crash "replace gave Ok for an invalid value"
		Err(InvalidValue) if !valid => {}
		Err(InvalidValue) => crash "replace gave InvalidValue for a valid value"
		Err(NoEntry) => crash "replace gave NoEntry"
	}

check_insert : Toml, Value, Bool -> {}
check_insert = |doc, value, valid| {
	t = match doc.table().get("t") {
		Ok(Value.Table(inner)) => inner
		_ => crash "no table t"
	}
	match doc.insert(["t", "e"], value) {
		Ok(edited) if valid => same(edited, doc.table().insert("t", Value.Table(t.insert("e", value))))
		Ok(_) => crash "insert gave Ok for an invalid value"
		Err(InvalidValue) if !valid => {}
		Err(InvalidValue) => crash "insert gave InvalidValue for a valid value"
		Err(_) => crash "insert gave KeyExists or NotATable"
	}
}

same : Toml, Dict(Str, Value) -> {}
same = |edited, expected| {
	if edited.table() != expected {
		crash "the table after the edit is wrong"
	}
	match Toml.parse(edited.to_str()) {
		Ok(again) if again.table() == expected => {}
		_ => crash "the edited text does not parse to the new table"
	}
}

target = Fuzz.target_with({
	name: "replace-date",
	generator: Input.generator_for(Default),
	test,
	show: |input| Str.inspect(input),
})
