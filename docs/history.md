
### Contents

  * [Introduction](./_introduction.md)
  * [Migrating from Ruby CSV](./migrating_from_csv.md)
  * [Parsing Strategy](./parsing_strategy.md)
  * [The Basic Read API](./basic_read_api.md)
  * [The Basic Write API](./basic_write_api.md)
  * [Batch Processing](././batch_processing.md)
  * [Configuration Options](./options.md)
  * [Row and Column Separators](./row_col_sep.md)
  * [Header Transformations](./header_transformations.md)
  * [Header Validations](./header_validations.md)
  * [Column Selection](./column_selection.md)
  * [Data Transformations](./data_transformations.md)
  * [Value Converters](./value_converters.md)
  * [Bad Row Quarantine](./bad_row_quarantine.md)
  * [Examples](./examples.md)
  * [**SmarterCSV over the Years**](./history.md)

--------------

# SmarterCSV over the Years

## Origin

SmarterCSV was born from a [StackOverflow question in 2011](https://stackoverflow.com/questions/7788618/update-mongodb-with-array-from-csv-join-table/7788746#7788746) about importing CSV data into MongoDB. The answer involved processing CSV rows as hashes — which turned out to be so useful that it became a gem.

The original write-up is preserved at [The original post](http://www.unixgods.org/Ruby/process_csv_as_hashes.html).

The first gem release was **v1.0.1 on 2012-07-30**.

---

## Key Milestones

| Version | Date       | Highlight |
|---------|------------|-----------|
| 1.0.1   | 2012-07-30 | First release: CSV → array of hashes, batch processing, key mapping |
| 1.0.17  | 2014-01-13 | `row_sep: :auto` — automatic row separator detection |
| 1.0.18  | 2014-10-27 | Multi-line / embedded-newline field support |
| 1.1.0   | 2015-07-26 | `value_converters` — custom per-column type parsing (dates, money, …) |
| 1.4.0   | 2022-02-11 | Experimental `col_sep: :auto` detection; switched to MIT-only licence |
| 1.5.1   | 2022-04-27 | `duplicate_header_suffix` for CSV files with repeated headers |
| 1.6.0   | 2022-05-03 | Complete rewrite of the pure-Ruby line parser |
| **1.7.0** | **2022-06-26** | **First C extension — >10× speedup over 1.6.x announced** |
| 1.8.0   | 2023-03-18 | `col_sep: :auto` and `row_sep: :auto` made the **default** |
| 1.9.0   | 2023-09-04 | Structured error objects with programmatic key access |
| 1.10.0  | 2023-12-31 | Performance & memory improvements; stricter `user_provided_headers` |
| **1.11.0** | **2024-07-02** | **SmarterCSV::Writer** — CSV generation from hashes |
| **1.12.0** | **2024-07-09** | **Thread-safe `SmarterCSV::Reader` class**; docs site added |
| 1.13.0  | 2024-11-06 | Auto-generation of extra column names; improved quote robustness |
| 1.14.0  | 2025-04-07 | Advanced Writer options; `header_converter` |
| 1.14.3  | 2025-05-04 | C-extension fast path for unquoted fields; inline whitespace stripping |
| **1.15.0** | **2026-02-04** | **Major C-extension rewrite — ~5× faster than 1.14.4; 39% less memory** |
| 1.15.1  | 2026-02-17 | Fix for backslash in quoted fields (`quote_escaping:` option) |
| 1.15.2  | 2026-02-20 | Further C-path optimisations; 5.4×–37.4× faster than 1.14.4 |
| **1.16.0** | **2026** | **`headers: { only: }` / `headers: { except: }` column selection (up to 16×); `nil_values_matching:`; Ruby-path Opt #10 & #11** |

---

## Performance Journey

Measured on Apple M1, Ruby 3.4.7. Protocol: 1 warm-up + 3 iterations, best time.
All times are **C-accelerated** except the `1.6.1` column (no C extension existed).

| File                        |  Rows |  Cols | 1.6.1 Rb (s) | 1.7.1 C (s) | 1.14.4 C (s) | 1.15.2 C (s) | 1.16.0 C (s) | total gain |
|-----------------------------|------:|------:|-------------:|------------:|-------------:|-------------:|-------------:|-----------:|
| fmap.csv                    |   50k |    14 |        2.130 |       0.873 |        0.748 |        0.076 |        0.065 |  **32.8x** |
| sample_10M.csv              |   50k |     4 |        1.291 |       0.661 |        0.471 |        0.064 |        0.050 |  **25.8x** |
| zipcode.csv                 |   44k |     7 |        1.572 |       0.797 |        0.581 |        0.087 |        0.057 |  **27.6x** |
| PEOPLE_IMPORT_NB.csv        |   50k |    13 |        3.746 |       1.053 |        1.608 |        0.109 |        0.078 |  **48.0x** |
| PEOPLE_IMPORT_NC.csv        |   50k |    17 |        3.831 |       1.018 |        1.520 |        0.092 |        0.078 |  **49.1x** |
| PEOPLE_IMPORT_B.csv         |   50k |    13 |        3.793 |       1.083 |        1.709 |        0.100 |        0.087 |  **43.6x** |
| PEOPLE_IMPORT_C.csv         |   50k |   116 |       21.612 |       2.763 |        8.425 |        0.206 |        0.200 | **108.1x** |
| PEOPLE_IMPORT_C_50k.csv     |   50k |   116 |       21.682 |       2.734 |        8.456 |        0.206 |        0.205 | **105.8x** |
| wide_500_cols_20k.csv       |   20k |   500 |       39.755 |       9.532 |       19.383 |        1.574 |        1.377 |  **28.9x** |
| long_fields_20k.csv         |   20k |     3 |        5.698 |       1.112 |        3.054 |        0.111 |        0.048 | **118.7x** |
| whitespace_heavy_20k.csv    |   20k |    10 |        1.335 |       0.393 |        0.596 |        0.032 |        0.030 |  **44.5x** |
| heavy_quoting_20k.csv       |   20k |    10 |        1.309 |       0.484 |        0.541 |        0.052 |        0.039 |  **33.6x** |
| many_empty_fields_20k.csv   |   20k |    20 |        1.149 |       0.420 |        0.413 |        0.031 |        0.027 |  **42.6x** |
| embedded_newlines_20k.csv   |   80k |     4 |        0.716 |       0.366 |        0.593 |        0.070 |        0.061 |  **11.7x** |
| utf8_multibyte_20k.csv      |   20k |     5 |        0.709 |       0.305 |        0.241 |        0.021 |        0.018 |  **39.4x** |
| embedded_separators_20k.csv |   20k |     5 |        0.714 |       0.333 |        0.301 |        0.036 |        0.024 |  **29.8x** |

`total gain` = v1.6.1 Ruby time / v1.16.0 C-accelerated time

**Highlights:**
- `long_fields_20k` (long quoted fields): **118.7x** — the field-scanning optimisations (`memchr` in C, `String#index` skip-ahead in Ruby) make long quoted fields essentially free to skip.
- `PEOPLE_IMPORT_C` / `PEOPLE_IMPORT_C_50k` (116 columns): **~106–108x** — wide rows benefit from every per-field saving multiplied across all columns.
- `wide_500_cols_20k` went from **39.8 seconds → 1.4 seconds** — and with `headers: { only: }` keeping just 2 of those 500 columns it drops further to **~0.1 seconds** (an additional ~16x on top).
- `embedded_newlines` shows the smallest gain (**11.7x**) — multi-line stitching is bounded by I/O and the line-counting loop, not field parsing.

---

## Related Reading

- [Parsing CSV Files in Ruby with SmarterCSV](https://tilo-sloboda.medium.com/parsing-csv-files-in-ruby-with-smartercsv-6ce66fb6cf38)
- [SmarterCSV 1.15.2 — Faster than raw CSV arrays](https://tilo-sloboda.medium.com/smartercsv-1-15-2-faster-than-raw-csv-arrays-benchmarks-zsv-and-the-full-pipeline-2c12a798032e)
- [Processing 1.4 Million CSV Records in Ruby, fast](https://lcx.wien/blog/processing-14-million-csv-records-in-ruby/)
- [Faster Parsing CSV with Parallel Processing](http://xjlin0.github.io/tech/2015/05/25/faster-parsing-csv-with-parallel-processing) by [Jack Lin](https://github.com/xjlin0/)

--------------------
PREVIOUS: [Examples](./examples.md) | UP: [README](../README.md)
