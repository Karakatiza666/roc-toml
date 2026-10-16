import Internal/Text as Text

## A TOML 1.0.0 value.
##
## A table is a `Dict(Str, Value)`. Two tables are equal when they have the
## same keys with equal values, in any order.
##
## A date is `{ year, month, day }`. A time is `{ hour, minute, second,
## nanosecond }`: a fraction of a second with more than 9 digits is truncated,
## not rounded (TOML 1.0.0, "Offset Date-Time"). An offset is in minutes east
## of UTC: `Z` is 0, `-07:00` is -420.
Value := [
	String(Str),
	Integer(I64),
	Float(F64),
	Boolean(Bool),
	OffsetDateTime(
		{
			date : { year : U16, month : U8, day : U8 },
			time : { hour : U8, minute : U8, second : U8, nanosecond : U32 },
			offset_minutes : I16,
		},
	),
	LocalDateTime(
		{
			date : { year : U16, month : U8, day : U8 },
			time : { hour : U8, minute : U8, second : U8, nanosecond : U32 },
		},
	),
	LocalDate({ year : U16, month : U8, day : U8 }),
	LocalTime({ hour : U8, minute : U8, second : U8, nanosecond : U32 }),
	Array(List(Value)),
	Table(Dict(Str, Value)),
].{

	## Structural equality, with one change: two `Float` NaN values are equal.
	## TOML has one value `nan` (TOML 1.0.0, "Float"), so a round trip of
	## `nan` gives an equal value.
	is_eq : Value, Value -> Bool
	is_eq = |a, b| same(a, b)

	## The value as TOML text on one line, as it is after `key = `.
	##
	## | Value | Text |
	## | --- | --- |
	## | String | A basic string. `"` and `\` get a backslash. U+0008, U+0009, U+000A, U+000C, U+000D are `\b \t \n \f \r`. Each other control character (U+0000 to U+001F, U+007F) is `\uXXXX`, uppercase hex. Other characters stay as they are. |
	## | Integer | Decimal |
	## | Float | `inf`, `-inf`, `nan`. Else `F64.to_str`, with `.0` added when that text has no `.` and no `e`: `1.0`, `-0.0`, `1e300` |
	## | Boolean | `true`, `false` |
	## | Dates and times | `1979-05-27T07:32:00.5-07:00`: `T`, the fraction only when it is not 0 and with no trailing zeros, `Z` for offset 0 |
	## | Array | `[1, "a"]`, `[]` |
	## | Table | An inline table: `{ a = 1, b = 2 }`, `{}`, keys in the order of the `Dict` |
	##
	## A key is bare when it is not empty and has only `A-Z a-z 0-9 _ -`. Else
	## it is a basic string, as a String value.
	print : Value -> Str
	print = |value| print_value(value)
}

same : Value, Value -> Bool
same = |a, b|
	match (a, b) {
		(String(x), String(y)) => x == y
		(Integer(x), Integer(y)) => x == y
		(Float(x), Float(y)) => (x.is_nan() and y.is_nan()) or x == y
		(Boolean(x), Boolean(y)) => x == y
		(OffsetDateTime(x), OffsetDateTime(y)) => x == y
		(LocalDateTime(x), LocalDateTime(y)) => x == y
		(LocalDate(x), LocalDate(y)) => x == y
		(LocalTime(x), LocalTime(y)) => x == y
		(Array(xs), Array(ys)) => same_lists(xs, ys)
		(Table(x), Table(y)) => same_tables(x, y)
		_ => Bool.False
	}

same_lists : List(Value), List(Value) -> Bool
same_lists = |xs, ys| xs.len() == ys.len() and List.map2(xs, ys, same).all(|ok| ok)

same_tables : Dict(Str, Value), Dict(Str, Value) -> Bool
same_tables = |x, y|
	x.len() == y.len()
		and x.to_list().all(
			|(k, v)|
				match y.get(k) {
					Ok(w) => same(v, w)
					Err(_) => Bool.False
				},
		)

print_value : Value -> Str
print_value = |value|
	match value {
		String(s) => Text.basic(s)
		Integer(n) => n.to_str()
		Float(f) => print_float(f)
		Boolean(b) => if b "true" else "false"
		OffsetDateTime({ date, time, offset_minutes }) => "${print_date(date)}T${print_time(time)}${print_offset(offset_minutes)}"
		LocalDateTime({ date, time }) => "${print_date(date)}T${print_time(time)}"
		LocalDate(date) => print_date(date)
		LocalTime(time) => print_time(time)
		Array(items) => "[${Str.join_with(items.map(print_value), ", ")}]"
		Table(t) => print_inline(t)
	}

print_inline : Dict(Str, Value) -> Str
print_inline = |t|
	if t.is_empty() {
		"{}"
	} else {
		pairs = t.to_list().map(|(k, v)| "${Text.key(k)} = ${print_value(v)}")
		"{ ${Str.join_with(pairs, ", ")} }"
	}

print_float : F64 -> Str
print_float = |f|
	if f.is_nan() {
		"nan"
	} else if f.is_infinite() {
		if f > 0 "inf" else "-inf"
	} else {
		s = f.to_str()
		if s.contains(".") or s.contains("e") s else "${s}.0"
	}

print_date : { year : U16, month : U8, day : U8 } -> Str
print_date = |{ year, month, day }| "${pad(year.to_u64(), 4)}-${pad(month.to_u64(), 2)}-${pad(day.to_u64(), 2)}"

print_time : { hour : U8, minute : U8, second : U8, nanosecond : U32 } -> Str
print_time = |{ hour, minute, second, nanosecond }| "${pad(hour.to_u64(), 2)}:${pad(minute.to_u64(), 2)}:${pad(second.to_u64(), 2)}${print_fraction(nanosecond)}"

# The fraction of a second, with no trailing zeros, or nothing for 0.
print_fraction : U32 -> Str
print_fraction = |ns|
	if ns == 0 {
		""
	} else {
		digits = pad(ns.to_u64(), 9).to_utf8()
		kept = digits.len() - count_trailing(digits, '0')
		".${Str.from_utf8_lossy(digits.take_first(kept))}"
	}

print_offset : I16 -> Str
print_offset = |minutes|
	if minutes == 0 {
		"Z"
	} else {
		size = minutes.to_i64().abs().to_u64_wrap()
		sign = if minutes < 0 "-" else "+"
		"${sign}${pad(size // 60, 2)}:${pad(size % 60, 2)}"
	}

# The number in decimal with zeros in front, to at least `width` digits.
pad : U64, U64 -> Str
pad = |n, width| {
	s = n.to_str()
	len = s.count_utf8_bytes()
	short = if len < width width - len else 0
	"${Str.repeat("0", short)}${s}"
}

count_trailing : List(U8), U8 -> U64
count_trailing = |bytes, b| {
	var $n = 0
	var $i = bytes.len()
	while $i > 0 and bytes.get($i - 1) == Ok(b) {
		$n = $n + 1
		$i = $i - 1
	}
	$n
}
