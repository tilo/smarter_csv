# SmarterCSV v2.0 TO DO List

DONE:
[X] Don't call rewind on filehandle
[X] use Procs for validations and transformatoins [issue #118](https://github.com/tilo/smarter_csv/issues/118)
[X] skip file opening, allow reading from CSV string, e.g. reading from S3 file [issue #120](https://github.com/tilo/smarter_csv/issues/120). Or stream large file from S3 (linked in the issue)
[X] [2.0 BUG]  convert_to_float saves Proc as @@convert_to_integer [issue #157](https://github.com/tilo/smarter_csv/issues/157)
[X] add enumerable to speed up parallel processing [issue #66](https://github.com/tilo/smarter_csv/issues/66), [issue #32](https://github.com/tilo/smarter_csv/issues/32)
[X] Provide an example for custom Procs for hash_transformations in the docs [issue #174](https://github.com/tilo/smarter_csv/issues/174)
[X] Collect all Errors, before surfacing them. Avoid throwing an exception on the first error [issue #133](https://github.com/tilo/smarter_csv/issues/133)


Partially Done:
[ ] make @errors and @warnings work [issue #118](https://github.com/tilo/smarter_csv/issues/118)

StilL TO DO:
[ ] Replace remove_empty_values: false [issue #213](https://github.com/tilo/smarter_csv/issues/213)

Arguably by design (e.g. exclude these columns from conversion and have them returned as a string)
[ ] [2.0 BUG] :convert_values_to_numeric_unless_leading_zeros drops leading zeros [issue #151](https://github.com/tilo/smarter_csv/issues/151)


## Numeric conversion: align the Ruby fallback path with the C path (permissive)

Context: `convert_values_to_numeric` runs in two places that currently DISAGREE on edge cases:
  - C path (`acceleration: true`, the default): `ext/smarter_csv/smarter_csv.c#try_numeric_conversion`
    uses `strtol`/`strtod` (base 10; float branch only entered when the field contains a `.`).
  - Ruby fallback (`acceleration: false`): `lib/smarter_csv/hash_transformations.rb` uses the
    strict regex `NUMERIC_REGEX = /\A[+-]?\d+(?:\.\d+)?\z/` plus `to_i` / `to_f`.

Divergence (verified empirically):
  | value     | C path           | Ruby fallback     |
  |-----------|------------------|-------------------|
  | ".5"      | 0.5 (Float)      | ".5" (String)     |
  | "3."      | 3.0 (Float)      | "3." (String)     |
  | "1.5e3"   | 1500.0 (Float)   | "1.5e3" (String)  |
  | "1.0e10"  | 10000000000.0    | "1.0e10" (String) |

Decision: the C path's permissive behavior (corner cases + scientific notation) is the intended
contract. Fix = make the Ruby fallback match the C path. Do NOT tighten the C path.

Ruby-side changes (in `hash_transformations.rb`):
  1. Swap NUMERIC_REGEX for a permissive one:
       /\A[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?\z/
     matches 1, 1., 1.5, .5, 1e3, 1.5e3, -3.14e-2, etc.; still rejects ".", "e3", "1.2.3",
     "1_000", "0x1F".
  2. Add `DOT_BYTE = '.'.ord` (46) and include it in the first-byte fast-reject's allowed set
     (the C pre-check already allows a leading `.`; without this, ".5" gets rejected on byte 0).
  3. Int-vs-float decision: `(v.include?('.') || v.include?('e') || v.include?('E')) ? v.to_f : v.to_i`
     (currently only checks for `.`).

Stays a string on BOTH paths (no change needed, but worth characterization tests — there are
currently NONE):
  - "010" => 10  (NOT octal 8 — both paths use base-10 conversion: String#to_i / strtol(.,10).
    A switch to Kernel#Integer() would break this. Lock it down with a test.)
  - "0x1F", "0b101", "0o17"  => string  (radix prefixes not honored by base-10 conversion)
  - "1_000"                  => string  (underscores)
  - "1,200.00", "1.300,00"   => string  (thousands sep / decimal comma — strtod stops at the
    separator → not fully consumed; regex rejects. This is the only safe behavior; "1,200" is
    genuinely ambiguous. Locale-specific number formats are the caller's job via value_converters.)

NOT doing: locale sniffing (read LC_NUMERIC at init and adjust the regexes). Rejected because
the machine locale tells you nothing about the file's number format, it breaks reproducibility
(same code + same file → different results on a US vs EU box), and `,` can't be both col_sep and
decimal separator anyway. Note `strtod` IS locale-sensitive (LC_NUMERIC) but it's dormant — Ruby
runs in the C/POSIX locale; don't deliberately activate it.

When done: parity tests (`[true, false].each`) for the now-consistent set (.5, 3., 1.5e3, 1e3)
plus characterization tests for the stays-a-string set above; CHANGELOG line noting the Ruby
fallback's numeric conversion now accepts scientific notation and bare-dot forms, matching the
accelerated path. Behavior change affects `acceleration: false` users only — and aligns them with
the default.
