app [main!] { pkg: "../package/main.roc" }

# Slice 1: the value forms of TOML 1.0.0 (https://toml.io/en/v1.0.0).
# Each case parses "v = <value>" and reads the key v.

import pkg.Toml
import pkg.Value

main! = |_args| Ok({})

v : Str -> Try(Value, [Bad])
v = |text|
	match Toml.parse("v = ${text}") {
		Ok(doc) => doc.get(["v"]).map_err(|_| Bad)
		Err(_) => Err(Bad)
	}

bad : Str -> Bool
bad = |text| Toml.parse("v = ${text}").is_err()

date : U16, U8, U8 -> { year : U16, month : U8, day : U8 }
date = |year, month, day| { year, month, day }

time : U8, U8, U8, U32 -> { hour : U8, minute : U8, second : U8, nanosecond : U32 }
time = |hour, minute, second, nanosecond| { hour, minute, second, nanosecond }

# V-STR1, TOML 1.0.0 "String": a basic string
expect v("\"I'm a string.\"") == Ok(Value.String("I'm a string."))

# V-STR2, "String": the escapes \b \t \n \f \r \" \\
expect v("\"a\\b\\t\\n\\f\\r\\\"\\\\z\"") == Ok(Value.String("a\u(8)\t\n\u(C)\r\"\\z"))

# V-STR3, "String": \uXXXX and \UXXXXXXXX are Unicode scalar values
expect v("\"\\u00E9\\U0001F600\"") == Ok(Value.String("\u(E9)\u(1F600)"))

# V-STR4, "String": an escape that is not in the list is an error
expect bad("\"\\q\"")

# V-STR5, "String": a surrogate code point is not a Unicode scalar value
expect bad("\"\\uD800\"")

# V-STR6, "String": a control character other than tab must be escaped
expect bad("\"a\u(1)b\"")

# V-STR7, "String": tab is allowed in a basic string
expect v("\"a\tb\"") == Ok(Value.String("a\tb"))

# V-STR8, "String": a literal string has no escapes
expect v("'C:\\Users\\nodejs\\templates'") == Ok(Value.String("C:\\Users\\nodejs\\templates"))

# V-STR9, "String": a newline right after the opening """ is trimmed
expect v("\"\"\"\nRoses\nViolets\"\"\"") == Ok(Value.String("Roses\nViolets"))

# V-STR10, "String": a line ending backslash trims the newline and the whitespace after it
expect v("\"\"\"\nThe quick \\\n\n   brown fox.\"\"\"") == Ok(Value.String("The quick brown fox."))

# V-STR11, "String": one or two quotes are allowed inside a multi-line basic string, also at its end
expect v("\"\"\"Here are two quotation marks: \"\". Simple.\"\"\"\"\"") == Ok(Value.String("Here are two quotation marks: \"\". Simple.\"\""))

# V-STR12, "String": a multi-line literal string keeps the backslash and trims the first newline
expect v("'''\nThe first newline is\ntrimmed in raw strings.\\n'''") == Ok(Value.String("The first newline is\ntrimmed in raw strings.\\n"))

# V-STR13, "String": a literal string cannot span lines
expect bad("'a\nb'")

# V-STR14, "String": an unterminated basic string is an error
expect bad("\"abc")

# V-STR15, Q8 (settled; TOML 1.0.0 "String" lets the parser choose): a CRLF in a multi-line string stays in the value
expect v("\"\"\"a\r\nb\"\"\"") == Ok(Value.String("a\r\nb"))
expect v("'''a\r\nb'''") == Ok(Value.String("a\r\nb"))

# V-INT1, TOML 1.0.0 "Integer": signs and decimal
expect v("+99") == Ok(Value.Integer(99))
expect v("-17") == Ok(Value.Integer(-17))
expect v("0") == Ok(Value.Integer(0))
expect v("-0") == Ok(Value.Integer(0))

# V-INT2, "Integer": an underscore between digits
expect v("1_000") == Ok(Value.Integer(1000))
expect v("5_349_221") == Ok(Value.Integer(5349221))

# V-INT3, "Integer": an underscore must have a digit on each side
expect bad("1__000")
expect bad("_1")
expect bad("1_")

# V-INT4, "Integer": a leading zero is not allowed
expect bad("01")
expect bad("+01")

# V-INT5, "Integer": hex, octal and binary with a prefix, case of hex digits free
expect v("0xDEADBEEF") == Ok(Value.Integer(3735928559))
expect v("0xdead_beef") == Ok(Value.Integer(3735928559))
expect v("0o755") == Ok(Value.Integer(493))
expect v("0b11010110") == Ok(Value.Integer(214))

# V-INT6, "Integer": no sign on a prefixed integer, and the prefix is lowercase
expect bad("+0x1")
expect bad("-0b1")
expect bad("0X1")

# V-INT8, "Integer": a binary integer has only the digits 0 and 1
expect bad("0b102")
expect bad("0b2")

# V-INT7, "Integer": the range is i64, a value out of range is an error
expect v("9223372036854775807") == Ok(Value.Integer(9223372036854775807))
expect v("-9223372036854775808") == Ok(Value.Integer(I64.lowest))
expect bad("9223372036854775808")
expect bad("-9223372036854775809")
expect bad("0x8000000000000000")

# V-FLT1, TOML 1.0.0 "Float": fractional and exponent parts
expect v("+1.0") == Ok(Value.Float(1.0))
expect v("3.1415") == Ok(Value.Float(3.1415))
expect v("-0.01") == Ok(Value.Float(-0.01))
expect v("5e+22") == Ok(Value.Float(5e22))
expect v("1e06") == Ok(Value.Float(1e6))
expect v("-2E-2") == Ok(Value.Float(-0.02))
expect v("6.626e-34") == Ok(Value.Float(6.626e-34))
expect v("224_617.445_991_228") == Ok(Value.Float(224617.445991228))

# V-FLT2, "Float": a decimal point needs a digit on each side
expect bad(".7")
expect bad("7.")
expect bad("3.e+20")

# V-FLT3, "Float": inf and nan, with an optional sign
expect v("inf") == Ok(Value.Float(F64.infinity))
expect v("+inf") == Ok(Value.Float(F64.infinity))
expect v("-inf") == Ok(Value.Float(-F64.infinity))
expect
	match v("nan") {
		Ok(Value.Float(f)) => f.is_nan()
		_ => Bool.False
	}
expect
	match v("-nan") {
		Ok(Value.Float(f)) => f.is_nan()
		_ => Bool.False
	}

# V-FLT4, "Float": -0.0 and +0.0 are valid
expect v("-0.0") == Ok(Value.Float(-0.0))
expect v("+0.0") == Ok(Value.Float(0.0))

# V-FLT5, "Float": the integer part follows the integer rules (no leading zero)
expect bad("03.14")

# V-FLT6, "Float": inf and nan are lowercase
expect bad("Inf")
expect bad("NaN")

# V-EQ1, Value.is_eq: two NaN values are equal, as TOML has one nan
expect Value.Float(F64.nan) == Value.Float(F64.nan)

# V-EQ2, Value.is_eq: different types are not equal
expect Value.Integer(1) != Value.Float(1.0)

# V-EQ3, Value.is_eq: tables compare keys and values, not their order
expect Value.Table(Dict.from_list([("a", Value.Integer(1)), ("b", Value.Boolean(Bool.True))])) == Value.Table(Dict.from_list([("b", Value.Boolean(Bool.True)), ("a", Value.Integer(1))]))

# V-BOOL1, TOML 1.0.0 "Boolean": always lowercase
expect v("true") == Ok(Value.Boolean(Bool.True))
expect v("false") == Ok(Value.Boolean(Bool.False))
expect bad("True")

# V-DT1, TOML 1.0.0 "Offset Date-Time": Z and a numeric offset
expect v("1979-05-27T07:32:00Z") == Ok(Value.OffsetDateTime({ date: date(1979, 5, 27), time: time(7, 32, 0, 0), offset_minutes: 0 }))
expect v("1979-05-27T00:32:00-07:00") == Ok(Value.OffsetDateTime({ date: date(1979, 5, 27), time: time(0, 32, 0, 0), offset_minutes: -420 }))

# V-DT2, "Offset Date-Time": a fraction of a second
expect v("1979-05-27T00:32:00.999999-07:00") == Ok(Value.OffsetDateTime({ date: date(1979, 5, 27), time: time(0, 32, 0, 999999000), offset_minutes: -420 }))

# V-DT3, "Offset Date-Time": a space can replace T
expect v("1979-05-27 07:32:00Z") == Ok(Value.OffsetDateTime({ date: date(1979, 5, 27), time: time(7, 32, 0, 0), offset_minutes: 0 }))

# V-DT4, "Offset Date-Time": precision beyond the implementation is truncated, not rounded (this package keeps nanoseconds)
expect v("1979-05-27T00:32:00.1234567899Z") == Ok(Value.OffsetDateTime({ date: date(1979, 5, 27), time: time(0, 32, 0, 123456789), offset_minutes: 0 }))

# V-DT5, "Local Date-Time"
expect v("1979-05-27T07:32:00") == Ok(Value.LocalDateTime({ date: date(1979, 5, 27), time: time(7, 32, 0, 0) }))

# V-DT6, "Local Date"
expect v("1979-05-27") == Ok(Value.LocalDate(date(1979, 5, 27)))

# V-DT7, "Local Time"
expect v("07:32:00") == Ok(Value.LocalTime(time(7, 32, 0, 0)))
expect v("00:32:00.999999") == Ok(Value.LocalTime(time(0, 32, 0, 999999000)))

# V-DT8, "Offset Date-Time" (RFC 3339 full-date): the day must exist in the month, with leap years
expect v("2000-02-29") == Ok(Value.LocalDate(date(2000, 2, 29)))
expect v("2024-02-29") == Ok(Value.LocalDate(date(2024, 2, 29)))
expect bad("2100-02-29")
expect bad("2023-02-29")
expect bad("2023-04-31")
expect bad("2023-13-01")
expect bad("2023-00-10")

# V-DT9, "Local Time" (RFC 3339 partial-time): hour 00-23, minute 00-59
expect bad("24:00:00")
expect bad("12:60:00")

# V-DT12, Q9 (settled; RFC 3339 time-second 00-60): second 60 on any date
expect v("23:59:60") == Ok(Value.LocalTime(time(23, 59, 60, 0)))
expect v("1990-12-31T23:59:60Z") == Ok(Value.OffsetDateTime({ date: date(1990, 12, 31), time: time(23, 59, 60, 0), offset_minutes: 0 }))
expect v("2023-06-15T12:00:60") == Ok(Value.LocalDateTime({ date: date(2023, 6, 15), time: time(12, 0, 60, 0) }))
expect bad("23:59:61")

# V-DT10, TOML 1.0.0: seconds are required (they are optional only from TOML 1.1.0)
expect bad("07:32")
expect bad("1979-05-27T07:32Z")

# V-DT11, RFC 3339 time-offset: hour and minute, both with 2 digits
expect bad("1979-05-27T07:32:00+7:00")
expect bad("1979-05-27T07:32:00+0700")

# V-ARR1, TOML 1.0.0 "Array": values with commas, and nested arrays
expect v("[ 1, 2, 3 ]") == Ok(Value.Array([Value.Integer(1), Value.Integer(2), Value.Integer(3)]))
expect v("[ [ 1, 2 ], [\"a\"] ]") == Ok(Value.Array([Value.Array([Value.Integer(1), Value.Integer(2)]), Value.Array([Value.String("a")])]))

# V-ARR2, "Array": values of different types can be mixed
expect v("[ 0.1, \"x\", true ]") == Ok(Value.Array([Value.Float(0.1), Value.String("x"), Value.Boolean(Bool.True)]))

# V-ARR3, "Array": newlines, comments and a trailing comma
expect v("[\n  1, # one\n  2,\n]") == Ok(Value.Array([Value.Integer(1), Value.Integer(2)]))

# V-ARR4, "Array": empty, and two commas are an error
expect v("[]") == Ok(Value.Array([]))
expect bad("[1,,2]")
expect bad("[,]")
expect bad("[1 2]")

# V-ARR5, "Array": an array of inline tables
expect v("[ { x = 1 }, {} ]") == Ok(Value.Array([Value.Table(Dict.from_list([("x", Value.Integer(1))])), Value.Table(Dict.empty())]))

# V-INL1, TOML 1.0.0 "Inline Table": keys and dotted keys
expect v("{ x = 1, y.z = \"a\" }") == Ok(Value.Table(Dict.from_list([("x", Value.Integer(1)), ("y", Value.Table(Dict.from_list([("z", Value.String("a"))])))])))

# V-INL2, "Inline Table": empty
expect v("{}") == Ok(Value.Table(Dict.empty()))

# V-INL3, "Inline Table": no newline and no trailing comma
expect bad("{ x = 1,\n y = 2 }")
expect bad("{ x = 1, }")

# V-INL4, "Inline Table": a duplicate key is an error
expect bad("{ x = 1, x = 2 }")

# V-VAL1, TOML 1.0.0 "Key/Value Pair": a value is required
expect Toml.parse("v = ").is_err()
expect Toml.parse("v = # no value").is_err()
