import parser.Parser
import parser.Utf8
import /Value
import Check

## The TOML 1.0.0 grammar (https://toml.io/en/v1.0.0, the ABNF) on
## roc-parser. A parse gives the lines of the document, with the spans of
## the keys and the values. A span position is the count of input bytes
## from that position to the end of the input.
##
## Each rule `x` is sealed: `x = Parser.lazy(|_| x_rule)`. The thunk captures
## nothing, so the type of `x` does not hold the types of the parsers in
## `x_rule`. Without the seals, the nested closure types make the LLVM build
## of a fuzz target take more than 10 minutes. `Parser.lazy` keeps the
## furthest failure of a rule that succeeds (`Parser.custom` with
## `Parser.run` does not), and the error column of a syntax error is that
## failure: the first byte that no alternative can take.
##
## The rules of the value recursion (value, array, inline table) use a named
## thunk function. On nightly-2026-10-14-38a3029, a cycle of top-level
## parsers through `Parser.lazy` and lambdas gives a binary that leaks memory
## when the build uses the compile cache. A named thunk does not leak.
Grammar :: [].{

	## A value with its span.
	Node := {
		form : [
			Scalar(Value),
			# A date or time with a field out of range, and the message.
			Odd(Value, Str),
			Arr(List(Node)),
			Inl(List({ keys : List({ name : Str, start : U64, end : U64 }), node : Node })),
		],
		start : U64,
		end : U64,
	}

	## The lines of a document, without the byte order mark.
	document : Parser(Utf8.Bytes, List([Head({ keys : List({ name : Str, start : U64, end : U64 }), array : Bool, start : U64, end : U64 }), Pair({ keys : List({ name : Str, start : U64, end : U64 }), node : Node }), Blank]))
	document = Parser.lazy(|_| document_rule)

	## Parses the bytes of a document without the byte order mark. The error
	## offset counts bytes from the start of `bytes`.
	parse : List(U8) -> Try(List([Head({ keys : List({ name : Str, start : U64, end : U64 }), array : Bool, start : U64, end : U64 }), Pair({ keys : List({ name : Str, start : U64, end : U64 }), node : Node }), Blank]), { offset : U64, message : Str })
	parse = |bytes| Utf8.parse_bytes(document, bytes).map_err(|ParseError(e)| e)
}

Key : { name : Str, start : U64, end : U64 }

Pair : { keys : List(Key), node : Grammar.Node }

Item : [Head({ keys : List(Key), array : Bool, start : U64, end : U64 }), Pair(Pair), Blank]

Form : [Scalar(Value), Odd(Value, Str), Arr(List(Grammar.Node)), Inl(List(Pair))]

Bytes : Utf8.Bytes

# --- Lines ---

document_rule : Parser(Bytes, List(Item))
document_rule = line.sep_by_one_or_more(newline)

line : Parser(Bytes, Item)
line = Parser.lazy(|_| line_rule)

line_rule : Parser(Bytes, Item)
line_rule =
	Parser.const(|item| item)
		.skip(ws)
		.keep(array_header.alt(table_header).alt(keyval.map(|p| Pair(p))).alt(Parser.const(Blank)))
		.skip(ws)
		.skip(comment.maybe())

array_header : Parser(Bytes, Item)
array_header = Parser.lazy(|_| array_header_rule)

array_header_rule : Parser(Bytes, Item)
array_header_rule = header_rule("[[", "]]", Bool.True)

table_header : Parser(Bytes, Item)
table_header = Parser.lazy(|_| table_header_rule)

table_header_rule : Parser(Bytes, Item)
table_header_rule = header_rule("[", "]", Bool.False)

header_rule : Str, Str, Bool -> Parser(Bytes, Item)
header_rule = |open, close, array|
	Parser.const(|start| |keys| |end| Head({ keys, array, start, end }))
		.keep(here)
		.skip(word(open))
		.skip(ws)
		.keep(key)
		.skip(ws)
		.skip(word(close))
		.keep(here)

keyval : Parser(Bytes, Pair)
keyval = Parser.lazy(keyval_thunk)

keyval_thunk : {} -> Parser(Bytes, Pair)
keyval_thunk = |_| keyval_rule

keyval_rule : Parser(Bytes, Pair)
keyval_rule =
	Parser.const(|keys| |node| { keys, node })
		.keep(key)
		.skip(ws)
		.skip(Utf8.codeunit('='))
		.skip(ws)
		.keep(value)

# --- Keys ---

key : Parser(Bytes, List(Key))
key = Parser.lazy(|_| key_rule)

key_rule : Parser(Bytes, List(Key))
key_rule = simple_key.sep_by_one_or_more(dot)

dot : Parser(Bytes, {})
dot = Parser.lazy(|_| dot_rule)

dot_rule : Parser(Bytes, {})
dot_rule = Parser.const({}).skip(ws).skip(Utf8.codeunit('.')).skip(ws)

simple_key : Parser(Bytes, Key)
simple_key = Parser.lazy(|_| simple_key_rule)

simple_key_rule : Parser(Bytes, Key)
simple_key_rule =
	Parser.const(|start| |name| |end| { name, start, end })
		.keep(here)
		.keep(bare_key.alt(basic_string).alt(literal_string))
		.keep(here)

bare_key : Parser(Bytes, Str)
bare_key = Parser.lazy(|_| bare_key_rule)

bare_key_rule : Parser(Bytes, Str)
bare_key_rule = span1(bare_class, "expected a key").map(Str.from_utf8_lossy)

# --- Values ---

value : Parser(Bytes, Grammar.Node)
value = Parser.lazy(value_thunk)

value_thunk : {} -> Parser(Bytes, Grammar.Node)
value_thunk = |_| value_rule

value_rule : Parser(Bytes, Grammar.Node)
value_rule =
	Parser.const(|start| |form| |end| Grammar.Node.{ form, start, end })
		.keep(here)
		.keep(form_of_value)
		.keep(here)

form_of_value : Parser(Bytes, Form)
form_of_value = Parser.lazy(form_of_value_thunk)

form_of_value_thunk : {} -> Parser(Bytes, Form)
form_of_value_thunk = |_| form_rule

# The alternatives in order: a float before an integer, a date before both.
form_rule : Parser(Bytes, Form)
form_rule =
	string_value.map(|s| Scalar(Value.String(s)))
		.alt(array)
		.alt(inline_table)
		.alt(boolean.map(|b| Scalar(Value.Boolean(b))))
		.alt(datetime)
		.alt(float.map(|r| rule_checked(r, |f| Value.Float(f))))
		.alt(integer.map(|r| rule_checked(r, |n| Value.Integer(n))))

array : Parser(Bytes, Form)
array = Parser.lazy(array_thunk)

array_thunk : {} -> Parser(Bytes, Form)
array_thunk = |_| array_rule

array_rule : Parser(Bytes, Form)
array_rule =
	Parser.const(|items| Arr(items))
		.skip(Utf8.codeunit('['))
		.skip(ws_comment_newline)
		.keep(array_items)
		.skip(Utf8.codeunit(']'))

array_items : Parser(Bytes, List(Grammar.Node))
array_items = Parser.lazy(array_items_thunk)

array_items_thunk : {} -> Parser(Bytes, List(Grammar.Node))
array_items_thunk = |_| array_items_rule

array_items_rule : Parser(Bytes, List(Grammar.Node))
array_items_rule =
	Parser.const(|items| |_| items)
		.keep(element.sep_by_one_or_more(comma_in_array))
		.keep(comma_in_array.maybe())
		.alt(Parser.const([]))

element : Parser(Bytes, Grammar.Node)
element = Parser.lazy(element_thunk)

element_thunk : {} -> Parser(Bytes, Grammar.Node)
element_thunk = |_| element_rule

element_rule : Parser(Bytes, Grammar.Node)
element_rule = Parser.const(|n| n).keep(value).skip(ws_comment_newline)

comma_in_array : Parser(Bytes, {})
comma_in_array = Parser.lazy(|_| comma_in_array_rule)

comma_in_array_rule : Parser(Bytes, {})
comma_in_array_rule = Parser.const({}).skip(Utf8.codeunit(',')).skip(ws_comment_newline)

inline_table : Parser(Bytes, Form)
inline_table = Parser.lazy(inline_table_thunk)

inline_table_thunk : {} -> Parser(Bytes, Form)
inline_table_thunk = |_| inline_table_rule

inline_table_rule : Parser(Bytes, Form)
inline_table_rule =
	Parser.const(|pairs| Inl(pairs))
		.skip(Utf8.codeunit('{'))
		.skip(ws)
		.keep(keyval.sep_by(comma_in_inline))
		.skip(ws)
		.skip(Utf8.codeunit('}'))

comma_in_inline : Parser(Bytes, {})
comma_in_inline = Parser.lazy(|_| comma_in_inline_rule)

comma_in_inline_rule : Parser(Bytes, {})
comma_in_inline_rule = Parser.const({}).skip(ws).skip(Utf8.codeunit(',')).skip(ws)

boolean : Parser(Bytes, Bool)
boolean = Parser.lazy(|_| boolean_rule)

boolean_rule : Parser(Bytes, Bool)
boolean_rule = word("true").map(|_| Bool.True).alt(word("false").map(|_| Bool.False))

# --- Strings ---

string_value : Parser(Bytes, Str)
string_value = Parser.lazy(|_| string_value_rule)

string_value_rule : Parser(Bytes, Str)
string_value_rule = ml_basic_string.alt(basic_string).alt(ml_literal_string).alt(literal_string)

basic_string : Parser(Bytes, Str)
basic_string = Parser.lazy(|_| basic_string_rule)

basic_string_rule : Parser(Bytes, Str)
basic_string_rule =
	Parser.const(|parts| Str.from_utf8_lossy(parts.join()))
		.skip(Utf8.codeunit('"'))
		.keep(basic_run.alt(escape).many())
		.skip(Utf8.codeunit('"'))

literal_string : Parser(Bytes, Str)
literal_string = Parser.lazy(|_| literal_string_rule)

literal_string_rule : Parser(Bytes, Str)
literal_string_rule =
	Parser.const(Str.from_utf8_lossy)
		.skip(Utf8.codeunit('\''))
		.keep(Utf8.span_class(literal_class))
		.skip(Utf8.codeunit('\''))

ml_basic_string : Parser(Bytes, Str)
ml_basic_string = Parser.lazy(|_| ml_basic_rule)

ml_basic_rule : Parser(Bytes, Str)
ml_basic_rule =
	Parser.const(|parts| |tail| Str.from_utf8_lossy(parts.join().concat(tail)))
		.skip(word("\"\"\""))
		.skip(newline.maybe())
		.keep(basic_run.alt(newline).alt(escaped_newline).alt(escape).alt(inner_double_quotes).many())
		.keep(closing_double_quotes)

ml_literal_string : Parser(Bytes, Str)
ml_literal_string = Parser.lazy(|_| ml_literal_rule)

ml_literal_rule : Parser(Bytes, Str)
ml_literal_rule =
	Parser.const(|parts| |tail| Str.from_utf8_lossy(parts.join().concat(tail)))
		.skip(word("'''"))
		.skip(newline.maybe())
		.keep(literal_run.alt(newline).alt(inner_single_quotes).many())
		.keep(closing_single_quotes)

basic_run : Parser(Bytes, List(U8))
basic_run = Parser.lazy(|_| basic_run_rule)

basic_run_rule : Parser(Bytes, List(U8))
basic_run_rule = span1(basic_class, "expected a character")

literal_run : Parser(Bytes, List(U8))
literal_run = Parser.lazy(|_| literal_run_rule)

literal_run_rule : Parser(Bytes, List(U8))
literal_run_rule = span1(literal_class, "expected a character")

escape : Parser(Bytes, List(U8))
escape = Parser.lazy(|_| escape_rule)

escape_rule : Parser(Bytes, List(U8))
escape_rule =
	Parser.const(|bytes| bytes)
		.skip(Utf8.codeunit('\\'))
		.keep(short_escape.alt(unicode_escape(4, 'u')).alt(unicode_escape(8, 'U')))

short_escape : Parser(Bytes, List(U8))
short_escape = Parser.lazy(|_| short_escape_rule)

short_escape_rule : Parser(Bytes, List(U8))
short_escape_rule = Utf8.codeunit_satisfies(is_short_escape).map(|b| [escaped_byte(b)])

# A backslash at the end of a line: the newline and the whitespace after it go.
escaped_newline : Parser(Bytes, List(U8))
escaped_newline = Parser.lazy(|_| escaped_newline_rule)

escaped_newline_rule : Parser(Bytes, List(U8))
escaped_newline_rule =
	Parser.const([])
		.skip(Utf8.codeunit('\\'))
		.skip(ws)
		.skip(newline)
		.skip(ws1.alt(newline).many())

is_short_escape : U8 -> Bool
is_short_escape = |b| b == 'b' or b == 't' or b == 'n' or b == 'f' or b == 'r' or b == '"' or b == '\\'

escaped_byte : U8 -> U8
escaped_byte = |b|
	match b {
		'b' => 0x08
		't' => 0x09
		'n' => 0x0A
		'f' => 0x0C
		'r' => 0x0D
		_ => b
	}

# The UTF-8 bytes of `\uXXXX` or `\UXXXXXXXX` (n hex digits after the letter).
unicode_escape : U64, U8 -> Parser(Bytes, List(U8))
unicode_escape = |n, letter|
	Parser.custom(
		|input| {
			digits = input.drop_first(1).take_first(n)
			if input.first() != Ok(letter) {
				Err(ParseError({ message: "expected an escape", offset: 0 }))
			} else if digits.len() == n and digits.all(is_hex) {
				code = digits.fold(0.U32, |acc, b| acc * 16 + hex_value(b).to_u32())
				if is_scalar(code) {
					Ok({ value: utf8_bytes(code), rest: input.drop_first(n + 1) })
				} else {
					Err(ParseError({ message: "not a Unicode scalar value", offset: 1 }))
				}
			} else {
				# The first byte that is not a hex digit.
				Err(ParseError({ message: "expected ${n.to_str()} hex digits", offset: 1 + count_while(digits, is_hex) }))
			}
		},
	)

count_while : List(U8), (U8 -> Bool) -> U64
count_while = |bytes, ok| {
	var $n = 0
	while bytes.get($n).map_ok(ok) == Ok(Bool.True) {
		$n = $n + 1
	}
	$n
}

is_scalar : U32 -> Bool
is_scalar = |c| c < 0xD800 or (c > 0xDFFF and c <= 0x10FFFF)

utf8_bytes : U32 -> List(U8)
utf8_bytes = |c|
	if c < 0x80 {
		[c.to_u8_wrap()]
	} else if c < 0x800 {
		[0xC0 + (c // 64).to_u8_wrap(), cont(c)]
	} else if c < 0x10000 {
		[0xE0 + (c // 4096).to_u8_wrap(), cont(c // 64), cont(c)]
	} else {
		[0xF0 + (c // 262144).to_u8_wrap(), cont(c // 4096), cont(c // 64), cont(c)]
	}

cont : U32 -> U8
cont = |c| 0x80 + (c % 64).to_u8_wrap()

inner_double_quotes : Parser(Bytes, List(U8))
inner_double_quotes = Parser.custom(|input| inner_quotes(input, '"'))

inner_single_quotes : Parser(Bytes, List(U8))
inner_single_quotes = Parser.custom(|input| inner_quotes(input, '\''))

closing_double_quotes : Parser(Bytes, List(U8))
closing_double_quotes = Parser.custom(|input| closing_quotes(input, '"'))

closing_single_quotes : Parser(Bytes, List(U8))
closing_single_quotes = Parser.custom(|input| closing_quotes(input, '\''))

# One or two quotes inside a multi-line string, when a byte that is not a quote follows.
inner_quotes : Bytes, U8 -> Parser.ParseResult(Bytes, List(U8))
inner_quotes = |input, q| {
	n = run_length(input, q)
	if (n == 1 or n == 2) and input.len() > n {
		Ok({ value: input.take_first(n), rest: input.drop_first(n) })
	} else {
		Err(ParseError({ message: "expected a character", offset: 0 }))
	}
}

# The closing delimiter of a multi-line string. Up to two quotes before it are content.
closing_quotes : Bytes, U8 -> Parser.ParseResult(Bytes, List(U8))
closing_quotes = |input, q| {
	n = run_length(input, q)
	if n >= 3 and n <= 5 {
		Ok({ value: input.take_first(n - 3), rest: input.drop_first(n) })
	} else {
		Err(ParseError({ message: "expected the end of the string", offset: 0 }))
	}
}

run_length : Bytes, U8 -> U64
run_length = |input, q| {
	var $n = 0
	while input.get($n) == Ok(q) {
		$n = $n + 1
	}
	$n
}

# --- Numbers ---

# An integer, or the message of a value out of the i64 range (a rule error).
integer : Parser(Bytes, Try(I64, Str))
integer = Parser.lazy(|_| integer_rule)

integer_rule : Parser(Bytes, Try(I64, Str))
integer_rule = hex_integer.alt(octal_integer).alt(binary_integer).alt(decimal_integer)

hex_integer : Parser(Bytes, Try(I64, Str))
hex_integer = Parser.lazy(|_| hex_integer_rule)

hex_integer_rule : Parser(Bytes, Try(I64, Str))
hex_integer_rule = radix_rule("0x", hex_digits, 16)

octal_integer : Parser(Bytes, Try(I64, Str))
octal_integer = Parser.lazy(|_| octal_integer_rule)

octal_integer_rule : Parser(Bytes, Try(I64, Str))
octal_integer_rule = radix_rule("0o", octal_digits, 8)

binary_integer : Parser(Bytes, Try(I64, Str))
binary_integer = Parser.lazy(|_| binary_integer_rule)

binary_integer_rule : Parser(Bytes, Try(I64, Str))
binary_integer_rule = radix_rule("0b", binary_digits, 2)

radix_rule : Str, Parser(Bytes, List(U8)), I64 -> Parser(Bytes, Try(I64, Str))
radix_rule = |prefix, digits, base|
	Parser.const(|ds| radix_value(ds, base))
		.skip(word(prefix))
		.keep(digits)

decimal_integer : Parser(Bytes, Try(I64, Str))
decimal_integer = Parser.lazy(|_| decimal_integer_rule)

decimal_integer_rule : Parser(Bytes, Try(I64, Str))
decimal_integer_rule =
	Parser.const(|s| |digits| I64.from_str(Str.from_utf8_lossy(minus(s).concat(digits))).map_err(|_| "integer out of range"))
		.keep(sign)
		.keep(unsigned_decimal)

# A float, or the message of a value that F64 cannot hold (a rule error).
float : Parser(Bytes, Try(F64, Str))
float = Parser.lazy(|_| float_rule)

float_rule : Parser(Bytes, Try(F64, Str))
float_rule = special_float.map(|f| Ok(f)).alt(decimal_float)

special_float : Parser(Bytes, F64)
special_float = Parser.lazy(|_| special_float_rule)

special_float_rule : Parser(Bytes, F64)
special_float_rule =
	Parser.const(|s| |name| if (name == "nan") F64.nan else if (negative(s)) -F64.infinity else F64.infinity)
		.keep(sign)
		.keep(word("inf").alt(word("nan")))

decimal_float : Parser(Bytes, Try(F64, Str))
decimal_float = Parser.lazy(|_| decimal_float_rule)

decimal_float_rule : Parser(Bytes, Try(F64, Str))
decimal_float_rule =
	Parser.const(|s| |int| |tail| F64.from_str(Str.from_utf8_lossy(minus(s).concat(int).concat(tail))).map_err(|_| "float out of range"))
		.keep(sign)
		.keep(unsigned_decimal)
		.keep(float_tail)

float_tail : Parser(Bytes, List(U8))
float_tail = Parser.lazy(|_| float_tail_rule)

float_tail_rule : Parser(Bytes, List(U8))
float_tail_rule = Parser.const(|frac| |exp| frac.concat(exp ?? [])).keep(fraction).keep(exponent.maybe()).alt(exponent)

fraction : Parser(Bytes, List(U8))
fraction = Parser.lazy(|_| fraction_rule)

fraction_rule : Parser(Bytes, List(U8))
fraction_rule = Parser.const(|digits| digits.prepend('.')).skip(Utf8.codeunit('.')).keep(decimal_digits)

exponent : Parser(Bytes, List(U8))
exponent = Parser.lazy(|_| exponent_rule)

exponent_rule : Parser(Bytes, List(U8))
exponent_rule =
	Parser.const(|s| |digits| ['e'].concat(minus(s)).concat(digits))
		.skip(Utf8.codeunit_satisfies(|b| b == 'e' or b == 'E'))
		.keep(sign)
		.keep(decimal_digits)

sign : Parser(Bytes, Try(U8, [Missing]))
sign = Parser.lazy(|_| sign_rule)

sign_rule : Parser(Bytes, Try(U8, [Missing]))
sign_rule = Utf8.codeunit_satisfies(|b| b == '+' or b == '-').maybe()

minus : Try(U8, [Missing]) -> List(U8)
minus = |s| if (negative(s)) ['-'] else []

negative : Try(U8, [Missing]) -> Bool
negative = |s| s == Ok('-')

# A decimal integer with no leading zero, without the underscores.
unsigned_decimal : Parser(Bytes, List(U8))
unsigned_decimal = Parser.lazy(|_| unsigned_decimal_rule)

unsigned_decimal_rule : Parser(Bytes, List(U8))
unsigned_decimal_rule = Parser.const(|first| |others| others.prepend(first))
	.keep(Utf8.codeunit_satisfies(|b| b >= '1' and b <= '9'))
	.keep(decimal_tail).alt(Utf8.codeunit('0').map(|z| [z]))

decimal_digits : Parser(Bytes, List(U8))
decimal_digits = Parser.lazy(|_| decimal_digits_rule)

decimal_digits_rule : Parser(Bytes, List(U8))
decimal_digits_rule = grouped(is_digit, decimal_tail)

decimal_tail : Parser(Bytes, List(U8))
decimal_tail = Parser.lazy(|_| decimal_tail_rule)

decimal_tail_rule : Parser(Bytes, List(U8))
decimal_tail_rule = group_tail(is_digit)

hex_digits : Parser(Bytes, List(U8))
hex_digits = Parser.lazy(|_| hex_digits_rule)

hex_digits_rule : Parser(Bytes, List(U8))
hex_digits_rule = grouped(is_hex, group_tail(is_hex))

octal_digits : Parser(Bytes, List(U8))
octal_digits = Parser.lazy(|_| octal_digits_rule)

octal_digits_rule : Parser(Bytes, List(U8))
octal_digits_rule = grouped(is_octal, group_tail(is_octal))

binary_digits : Parser(Bytes, List(U8))
binary_digits = Parser.lazy(|_| binary_digits_rule)

binary_digits_rule : Parser(Bytes, List(U8))
binary_digits_rule = grouped(is_binary, group_tail(is_binary))

# Digits with one underscore between two digits, without the underscores.
grouped : (U8 -> Bool), Parser(Bytes, List(U8)) -> Parser(Bytes, List(U8))
grouped = |is_d, tail|
	Parser.const(|first| |others| others.prepend(first))
		.keep(Utf8.codeunit_satisfies(is_d))
		.keep(tail)

group_tail : (U8 -> Bool) -> Parser(Bytes, List(U8))
group_tail = |is_d| {
	d = Utf8.codeunit_satisfies(is_d)
	d.alt(Parser.const(|b| b).skip(Utf8.codeunit('_')).keep(d)).many()
}

radix_value : List(U8), I64 -> Try(I64, Str)
radix_value = |digits, base| {
	var $n = 0.I64
	for b in digits {
		times = $n.times_try(base) ? |_| "integer out of range"
		$n = times.plus_try(hex_value(b).to_i64()) ? |_| "integer out of range"
	}
	Ok($n)
}

is_digit : U8 -> Bool
is_digit = |b| b >= '0' and b <= '9'

is_hex : U8 -> Bool
is_hex = |b| is_digit(b) or (b >= 'a' and b <= 'f') or (b >= 'A' and b <= 'F')

is_octal : U8 -> Bool
is_octal = |b| b >= '0' and b <= '7'

is_binary : U8 -> Bool
is_binary = |b| b == '0' or b == '1'

hex_value : U8 -> U8
hex_value = |b| if (is_digit(b)) b - '0' else if (b >= 'a') b - 'a' + 10 else b - 'A' + 10

# --- Dates and times (RFC 3339) ---

Date : { year : U16, month : U8, day : U8 }

Time : { hour : U8, minute : U8, second : U8, nanosecond : U32 }

Offset : { minutes : I16, ok : Bool }

datetime : Parser(Bytes, Form)
datetime = Parser.lazy(|_| datetime_rule)

datetime_rule : Parser(Bytes, Form)
datetime_rule = offset_date_time.alt(local_date_time).alt(local_date).alt(local_time)

offset_date_time : Parser(Bytes, Form)
offset_date_time = Parser.lazy(|_| offset_date_time_rule)

offset_date_time_rule : Parser(Bytes, Form)
offset_date_time_rule =
	Parser.const(|d| |t| |o| checked(Value.OffsetDateTime({ date: d, time: t, offset_minutes: o.minutes }), [Check.date_problem(d), Check.time_problem(t), if (o.ok) "" else "offset out of range"]))
		.keep(date)
		.skip(time_delimiter)
		.keep(time)
		.keep(offset)

local_date_time : Parser(Bytes, Form)
local_date_time = Parser.lazy(|_| local_date_time_rule)

local_date_time_rule : Parser(Bytes, Form)
local_date_time_rule =
	Parser.const(|d| |t| checked(Value.LocalDateTime({ date: d, time: t }), [Check.date_problem(d), Check.time_problem(t)]))
		.keep(date)
		.skip(time_delimiter)
		.keep(time)

local_date : Parser(Bytes, Form)
local_date = Parser.lazy(|_| local_date_rule)

local_date_rule : Parser(Bytes, Form)
local_date_rule = date.map(|d| checked(Value.LocalDate(d), [Check.date_problem(d)]))

local_time : Parser(Bytes, Form)
local_time = Parser.lazy(|_| local_time_rule)

local_time_rule : Parser(Bytes, Form)
local_time_rule = time.map(|t| checked(Value.LocalTime(t), [Check.time_problem(t)]))

checked : Value, List(Str) -> Form
checked = |v, problems|
	match problems.find_first(|p| !p.is_empty()) {
		Ok(problem) => Odd(v, problem)
		Err(_) => Scalar(v)
	}

date : Parser(Bytes, Date)
date = Parser.lazy(|_| date_rule)

date_rule : Parser(Bytes, Date)
date_rule =
	Parser.const(|year| |month| |day| { year, month, day })
		.keep(four_digits)
		.skip(Utf8.codeunit('-'))
		.keep(two_digits)
		.skip(Utf8.codeunit('-'))
		.keep(two_digits)

time : Parser(Bytes, Time)
time = Parser.lazy(|_| time_rule)

time_rule : Parser(Bytes, Time)
time_rule =
	Parser.const(|hour| |minute| |second| |ns| { hour, minute, second, nanosecond: ns ?? 0 })
		.keep(two_digits)
		.skip(Utf8.codeunit(':'))
		.keep(two_digits)
		.skip(Utf8.codeunit(':'))
		.keep(two_digits)
		.keep(second_fraction.maybe())

second_fraction : Parser(Bytes, U32)
second_fraction = Parser.lazy(|_| second_fraction_rule)

second_fraction_rule : Parser(Bytes, U32)
second_fraction_rule = Parser.const(nanoseconds).skip(Utf8.codeunit('.')).keep(Utf8.codeunit_satisfies(is_digit).one_or_more())

time_delimiter : Parser(Bytes, U8)
time_delimiter = Utf8.codeunit_satisfies(|b| b == 'T' or b == 't' or b == ' ')

offset : Parser(Bytes, Offset)
offset = Parser.lazy(|_| offset_rule)

offset_rule : Parser(Bytes, Offset)
offset_rule = zulu.alt(numeric_offset)

zulu : Parser(Bytes, Offset)
zulu = Utf8.codeunit_satisfies(|b| b == 'Z' or b == 'z').map(|_| { minutes: 0, ok: Bool.True })

numeric_offset : Parser(Bytes, Offset)
numeric_offset = Parser.lazy(|_| numeric_offset_rule)

numeric_offset_rule : Parser(Bytes, Offset)
numeric_offset_rule =
	Parser.const(|s| |h| |m| { minutes: (if (s == '-') -1 else 1) * (h.to_i16() * 60 + m.to_i16()), ok: h <= 23 and m <= 59 })
		.keep(Utf8.codeunit_satisfies(|b| b == '+' or b == '-'))
		.keep(two_digits)
		.skip(Utf8.codeunit(':'))
		.keep(two_digits)

digit : Parser(Bytes, U8)
digit = Utf8.codeunit_satisfies(is_digit).map(|b| b - '0')

two_digits : Parser(Bytes, U8)
two_digits = Parser.lazy(|_| two_digits_rule)

two_digits_rule : Parser(Bytes, U8)
two_digits_rule = Parser.const(|a| |b| a * 10 + b).keep(digit).keep(digit)

four_digits : Parser(Bytes, U16)
four_digits = Parser.lazy(|_| four_digits_rule)

four_digits_rule : Parser(Bytes, U16)
four_digits_rule = Parser.const(|a| |b| (a.to_u16() * 100 + b.to_u16())).keep(two_digits).keep(two_digits)

# The first 9 digits of a fraction of a second, as nanoseconds. More digits are truncated.
nanoseconds : List(U8) -> U32
nanoseconds = |digits| {
	first = digits.take_first(9)
	n = first.fold(0.U32, |acc, b| acc * 10 + (b - '0').to_u32())
	List.repeat(0, 9 - first.len()).fold(n, |acc, _| acc * 10)
}

# A number, or a rule error at the start of the value.
rule_checked : Try(n, Str), (n -> Value) -> Form
rule_checked = |r, make|
	match r {
		Ok(n) => Scalar(make(n))
		Err(m) => Odd(Value.Boolean(Bool.False), m)
	}

# The exact bytes of `text`. A failure is at the first byte that differs, so
# the error column is where the text can no longer match.
word : Str -> Parser(Bytes, Str)
word = |text| {
	expected = text.to_utf8()
	message = "expected `${text}`"
	Parser.custom(
		|input| {
			n = expected.len()
			if input.take_first(n) == expected {
				Ok({ value: text, rest: input.drop_first(n) })
			} else {
				Err(ParseError({ message, offset: common_prefix(input, expected) }))
			}
		},
	)
}

common_prefix : List(U8), List(U8) -> U64
common_prefix = |a, b| {
	var $i = 0
	while $i < b.len() and a.get($i) == b.get($i) {
		$i = $i + 1
	}
	$i
}

# --- Whitespace, comments, newlines ---

here : Parser(Bytes, U64)
here = Parser.custom(|input| Ok({ value: input.len(), rest: input }))

ws : Parser(Bytes, Bytes)
ws = Utf8.span_class(ws_class)

ws1 : Parser(Bytes, List(U8))
ws1 = Parser.lazy(|_| ws1_rule)

ws1_rule : Parser(Bytes, List(U8))
ws1_rule = span1(ws_class, "expected whitespace")

newline : Parser(Bytes, List(U8))
newline = Parser.lazy(|_| newline_rule)

newline_rule : Parser(Bytes, List(U8))
newline_rule = Utf8.codeunit('\n').map(|_| ['\n']).alt(word("\r\n").map(|_| ['\r', '\n']))

comment : Parser(Bytes, Bytes)
comment = Parser.lazy(|_| comment_rule)

comment_rule : Parser(Bytes, Bytes)
comment_rule = Parser.const(|b| b).skip(Utf8.codeunit('#')).keep(Utf8.span_class(comment_class))

ws_comment_newline : Parser(Bytes, List({}))
ws_comment_newline = Parser.lazy(|_| ws_comment_newline_rule)

ws_comment_newline_rule : Parser(Bytes, List({}))
ws_comment_newline_rule = ws1.ignore().alt(comment.ignore()).alt(newline.ignore()).many()

# A run of one or more bytes of the class.
span1 : Utf8.ByteClass, Str -> Parser(Bytes, Bytes)
span1 = |class, message| Utf8.span_class(class).map(|b| if (b.is_empty()) Err(message) else Ok(b)).flatten()

ws_class : Utf8.ByteClass
ws_class = Utf8.ByteClass.from_bytes([' ', '\t'])

bare_class : Utf8.ByteClass
bare_class = Utf8.ByteClass.from_predicate(|b| (b >= 'A' and b <= 'Z') or (b >= 'a' and b <= 'z') or is_digit(b) or b == '_' or b == '-')

# Tab, and each byte that is not a control character. Bytes of non-ASCII characters are in it.
comment_class : Utf8.ByteClass
comment_class = Utf8.ByteClass.from_predicate(|b| b == '\t' or (b >= 0x20 and b != 0x7F))

basic_class : Utf8.ByteClass
basic_class = Utf8.ByteClass.from_predicate(|b| b == '\t' or (b >= 0x20 and b != 0x7F and b != '"' and b != '\\'))

literal_class : Utf8.ByteClass
literal_class = Utf8.ByteClass.from_predicate(|b| b == '\t' or (b >= 0x20 and b != 0x7F and b != '\''))
