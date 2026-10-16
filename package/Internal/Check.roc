import /Value

## The ranges of dates and times that TOML text can have (RFC 3339 and
## TOML 1.0.0). `parse` uses them for the text, and `replace` and
## `insert` for a new value.
Check :: [].{

	## The problem of a date, or the empty text when it exists.
	date_problem : { year : U16, month : U8, day : U8 } -> Str
	date_problem = |{ year, month, day }|
		if year > 9999 {
			"year out of range"
		} else if month < 1 or month > 12 {
			"month out of range"
		} else if day < 1 or day > days_in_month(year, month) {
			"day out of range"
		} else {
			""
		}

	## The problem of a time, or the empty text when it is valid.
	time_problem : { hour : U8, minute : U8, second : U8, nanosecond : U32 } -> Str
	time_problem = |{ hour, minute, second, nanosecond }|
		if hour > 23 {
			"hour out of range"
		} else if minute > 59 {
			"minute out of range"
		} else if second > 60 {
			"second out of range"
		} else if nanosecond > 999_999_999 {
			"fraction of a second out of range"
		} else {
			""
		}

	## True for an offset that TOML text can have: -23:59 to +23:59.
	offset_ok : I16 -> Bool
	offset_ok = |minutes| minutes >= -1439 and minutes <= 1439

	## True when each date and time in the value, also in arrays and inline
	## tables, has TOML text that `parse` reads back as the same value.
	value_ok : Value -> Bool
	value_ok = |value|
		match value {
			Value.OffsetDateTime({ date, time, offset_minutes }) => date_problem(date).is_empty() and time_problem(time).is_empty() and Check.offset_ok(offset_minutes)
			Value.LocalDateTime({ date, time }) => date_problem(date).is_empty() and time_problem(time).is_empty()
			Value.LocalDate(date) => date_problem(date).is_empty()
			Value.LocalTime(time) => time_problem(time).is_empty()
			Value.Array(items) => items.all(Check.value_ok)
			Value.Table(t) => t.to_list().all(|(_, v)| Check.value_ok(v))
			_ => Bool.True
		}
}

days_in_month : U16, U8 -> U8
days_in_month = |year, month|
	match month {
		2 => if (year % 4 == 0 and year % 100 != 0) or year % 400 == 0 29 else 28
		4 | 6 | 9 | 11 => 30
		_ => 31
	}
