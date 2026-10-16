## The text forms of strings and keys, shared by `Value.print` and the edits.
Text :: [].{

	## A basic string: `"`, `\` and control characters get escapes.
	basic : Str -> Str
	basic = |s| quoted(s, Bool.False)

	## The body of a multi-line basic string: as `basic`, but a newline is a
	## raw `\n`, and no quotes go around it.
	ml_body : Str -> Str
	ml_body = |s| Str.from_utf8_lossy(escape_bytes(s.to_utf8(), Bool.True))

	## A key: bare when it is not empty and has only `A-Z a-z 0-9 _ -`, else
	## a basic string.
	key : Str -> Str
	key = |k| if is_bare(k) k else basic(k)

	## The keys of a path, joined with dots.
	path : List(Str) -> Str
	path = |keys| Str.join_with(keys.map(Text.key), ".")

	## True for a byte of a bare key.
	is_bare_byte : U8 -> Bool
	is_bare_byte = |b| (b >= 'A' and b <= 'Z') or (b >= 'a' and b <= 'z') or (b >= '0' and b <= '9') or b == '_' or b == '-'

	## True for a control character (U+0000 to U+001F, U+007F).
	is_control : U8 -> Bool
	is_control = |b| b < 0x20 or b == 0x7F
}

is_bare : Str -> Bool
is_bare = |k| {
	bytes = k.to_utf8()
	!bytes.is_empty() and bytes.all(Text.is_bare_byte)
}

quoted : Str, Bool -> Str
quoted = |s, raw_newline| Str.from_utf8_lossy(['"'].concat(escape_bytes(s.to_utf8(), raw_newline)).append('"'))

escape_bytes : List(U8), Bool -> List(U8)
escape_bytes = |bytes, raw_newline| {
	var $out = List.with_capacity(bytes.len() + 2)
	for b in bytes {
		$out = $out.concat(escape_byte(b, raw_newline))
	}
	$out
}

escape_byte : U8, Bool -> List(U8)
escape_byte = |b, raw_newline|
	match b {
		'"' => ['\\', '"']
		'\\' => ['\\', '\\']
		0x08 => ['\\', 'b']
		0x09 => ['\\', 't']
		0x0A => if raw_newline ['\n'] else ['\\', 'n']
		0x0C => ['\\', 'f']
		0x0D => ['\\', 'r']
		_ => if Text.is_control(b) ['\\', 'u', '0', '0', hex_digit(b // 16), hex_digit(b % 16)] else [b]
	}

hex_digit : U8 -> U8
hex_digit = |n| if n < 10 '0' + n else 'A' + n - 10
