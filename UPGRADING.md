# Upgrading SmarterCSV

> [!TIP]
> Prefer the interactive [Upgrade Wizard](https://tilo.github.io/smarter_csv/upgrade_wizard.html) for a guided walk-through with Yes/No questions.  
> This document is auto-generated from `CHANGELOG.md` and `docs/upgrade_path.json` by `bin/gen-upgrading-md`.

## How to use this guide

1. Find your current version below. **Newest releases appear first; older ones further down.**
2. Read each series section between yours and the latest at the top. For each one, check whether any **If** conditions apply to your code.
3. If none apply, you can upgrade all the way through that series with no code changes.

Prefer an interactive walk-through? The [Upgrade Wizard](https://tilo.github.io/smarter_csv/upgrade_wizard.html) asks one question at a time and only shows the migration steps that apply to your code.

**Latest release:** `1.17.2` (in the `1.17.x` series).

---

## 1.17.x — latest series

**Versions in this series:**  
[1.17.0, 1.17.1, 1.17.2]

**Latest release:** `1.17.2`

Update your Gemfile to:

```ruby
gem 'smarter_csv', '~> 1.17.0'
```

Then run `bundle update smarter_csv`.

## Series 1.16 → 1.17

**Upgrading from any 1.16 version:**  
[1.16.0, 1.16.1, 1.16.2, 1.16.3, 1.16.4, 1.16.5, 1.16.6]

> ⚠️ **In-series notes** worth checking if you're crossing through one of these:
> - **1.16.1:** **Fibers:** `SmarterCSV.errors` uses `Thread.current` for storage, which is **shared across all fibers running in the same thread**. If you process CSV files concurrently in fibers (e.g. with `Async`, `Falcon`, or manual `Fiber` scheduling), `SmarterCSV.errors` may return stale or wrong results. **Use `SmarterCSV::Reader` directly** — errors are scoped to the reader instance and are always correct regardless of fiber context.
> - **1.16.2:** If your code references auto-generated keys for blank headers, update those to use the absolute column position.

**Crossing to 1.17.x** (latest: `1.17.2`): you can upgrade all the way — no code changes needed.

---

## Series 1.15 → 1.16

**Upgrading from any 1.15 version:**  
[1.15.0, 1.15.1, 1.15.2, 1.15.3]

**Crossing to 1.16.x** (latest: `1.16.6`):

- **If** your CSV files contain stray `"` characters in the middle of unquoted fields:  
  → verify the output is now correct — 1.16.0 treats them as literal (RFC 4180). Output gets more correct for almost everyone; the temporary escape hatch `quote_boundary: :legacy` exists if your downstream code depended on the previously-corrupted output (not recommended for new code).

---

## Series 1.14 → 1.15

**Upgrading from any 1.14 version:**  
[1.14.0, 1.14.1, 1.14.2, 1.14.3, 1.14.4]

**Crossing to 1.15.x** (latest: `1.15.3`):

- **If** your Ruby version is 2.5 or older:  
  → upgrade Ruby to 2.6 or newer — 1.15.0 dropped support for Ruby 2.5.
    
    The migration is small: Ruby 2.5 reached end-of-life in March 2021 (no more security fixes anywhere), and Ruby 2.5 → 2.6 is API-compatible for nearly all code. Update your `.ruby-version` or the `ruby` line in your `Gemfile`, run `bundle install`, and you're done. Most users jump straight to a current Ruby (3.x).

---

## Series 1.13 → 1.14

**Upgrading from any 1.13 version:**  
[1.13.0, 1.13.1]

**Crossing to 1.14.x** (latest: `1.14.4`): you can upgrade all the way — no code changes needed.

---

## Series 1.12 → 1.13

**Upgrading from any 1.12 version:**  
[1.12.0, 1.12.1]

**Crossing to 1.13.x** (latest: `1.13.1`):

- **If** your CSV rows can have more columns than the header AND your code expects only header-listed keys:  
  → filter out the new auto-generated `:column_N` keys, or pass `strict: true` to raise on extras — 1.13.0 keeps extra columns instead of dropping them silently.

- **If** any of your input files might have unbalanced quotes:  
  → wrap calls in `rescue SmarterCSV::MalformedCSV` — 1.13.0 now raises instead of producing garbled output.

- **If** you pass `user_provided_headers:` AND your file has a header line that should be skipped:  
  → also pass `headers_in_file: true` explicitly — 1.13.0 made `user_provided_headers:` imply `headers_in_file: false` by default.

---

## Series 1.11 → 1.12

**Upgrading from any 1.11 version:**  
[1.11.0, 1.11.2]

**Crossing to 1.12.x** (latest: `1.12.1`):

- **If** you call `SmarterCSV.process` and need to inspect headers / warnings / errors after parsing:  
  → switch to using `reader = SmarterCSV::Reader.new(file, options); reader.process`.
    
    Version 1.11 class-level accessors `SmarterCSV.headers` / `SmarterCSV.raw_header` are gone in 1.12.0 — if you used those, see the next question.

- **If** you call `SmarterCSV.raw_headers` or `SmarterCSV.headers`:  
  → switch to instantiating `SmarterCSV::Reader` and reading `reader.raw_headers` / `reader.headers` — 1.12.0 moved these off the class-level API.

---

## Series 1.10 → 1.11

**Upgrading from any 1.10 version:**  
[1.10.0, 1.10.1, 1.10.2, 1.10.3]

**Crossing to 1.11.x** (latest: `1.11.2`): you can upgrade all the way — no code changes needed.

---

## Series 1.9 → 1.10

**Upgrading from any 1.9 version:**  
[1.9.0, 1.9.2, 1.9.3]

**Crossing to 1.10.x** (latest: `1.10.3`):

- **If** you use `user_provided_headers:`:  
  → write the list in the exact final form you want (all symbols *or* all strings) — 1.10.0 stopped applying additional transformations. `strings_as_keys:` is ignored alongside it.

- **If** your `user_provided_headers:` list contains duplicate entries:  
  → remove the duplicates — 1.10.0 raises `SmarterCSV::DuplicateHeaders`.

- **If** you depended on duplicate-header detection failing fast:  
  → pass `duplicate_header_suffix: nil` explicitly — 1.10.0 changed the default to `''` (it auto-disambiguates duplicates as `name`, `name2`, ...).

---

## Series 1.8 → 1.9

**Upgrading from any 1.8 version:**  
[1.8.0, 1.8.1, 1.8.2, 1.8.3, 1.8.4, 1.8.5]

**Crossing to 1.9.x** (latest: `1.9.3`):

- **If** you rescue `SmarterCSV::MissingHeaders`:  
  → rename it to `SmarterCSV::MissingKeys` — 1.9.0 renamed the error.

- **If** you use `key_mapping:` and want to allow some mapped headers to be missing:  
  → pass `silence_missing_keys: true` — 1.9.0 now raises `MissingKeys` for unmapped headers (this makes them optional).

---

## Series 1.7 → 1.8

**Upgrading from any 1.7 version:**  
[1.7.0.pre1, 1.7.0.pre5, 1.7.1, 1.7.2, 1.7.3, 1.7.4]

**Crossing to 1.8.x** (latest: `1.8.5`):

- **If** you accept CSV files from users or other external sources where the column separator might not be a comma (e.g. locale-specific exports using `;` or tab), or where a file might have only one column:  
  → wrap your `SmarterCSV.process` calls in `rescue SmarterCSV::NoColSepDetected` — 1.8.0 made `col_sep: :auto` and `row_sep: :auto` the new defaults, but in rare cases it raises when separators could not be found.

---

## Series 1.6 → 1.7

**Upgrading from any 1.6 version:**  
[1.6.0, 1.6.1]

**Crossing to 1.7.x** (latest: `1.7.4`): you can upgrade all the way — no code changes needed.

---

## Series 1.5 → 1.6

**Upgrading from any 1.5 version:**  
[1.5.0, 1.5.1, 1.5.2]

**Crossing to 1.6.x** (latest: `1.6.1`):

- **If** you rescue an exception when `key_mapping:` has an unused key:  
  → remove that rescue clause — 1.6.1 changed this from an exception to a warning.

---

## Series 1.4 → 1.5

**Upgrading from any 1.4 version:**  
[1.4.0, 1.4.2]

**Crossing to 1.5.x** (latest: `1.5.2`):

- **If** you relied on lines starting with `#` being treated as comments:  
  → pass `comment_regexp: /\A#/` explicitly — 1.5.0 changed the default to `nil`.

---

## Series 1.3 → 1.4

**Upgrading from any 1.3 version:**  
[1.3.0]

**Crossing to 1.4.x** (latest: `1.4.2`): you can upgrade all the way — no code changes needed.

---

## Series 1.2 → 1.3

**Upgrading from any 1.2 version:**  
[1.2.0, 1.2.3, 1.2.4, 1.2.5, 1.2.6, 1.2.7, 1.2.8]

**Crossing to 1.3.x** (latest: `1.3.0`):

- **If** you use `key_mapping:`:  
  → switch hash values to symbols (or update downstream reads to use string keys) — 1.3.0 stopped silently coercing values to symbols.

---

## Series 1.1 → 1.2

**Upgrading from any 1.1 version:**  
[1.1.0, 1.1.1, 1.1.2, 1.1.3, 1.1.4, 1.1.5]

**Crossing to 1.2.x** (latest: `1.2.8`):

- **If** your CSV files have duplicate header names:  
  → rename the duplicates, or be ready to rescue `SmarterCSV::DuplicateHeaders` — 1.2.0 added default validation that each header appears only once and raises this exception when it doesn't.

---

## Series 1.0 → 1.1

**Upgrading from any 1.0 version:**  
[1.0.0.pre1, 1.0.0, 1.0.1, 1.0.2, 1.0.3, 1.0.4, 1.0.5, 1.0.6, 1.0.7, 1.0.8, 1.0.9, 1.0.10, 1.0.11, 1.0.12, 1.0.14, 1.0.15, 1.0.16, 1.0.17, 1.0.18, 1.0.19]

**Crossing to 1.1.x** (latest: `1.1.5`):

- **If** you set `headers_in_file: false`:  
  → also provide `user_provided_headers:` — 1.1.0 now raises an error if you set the former without the latter.

---

---

Questions? Open an issue: <https://github.com/tilo/smarter_csv/issues>.
