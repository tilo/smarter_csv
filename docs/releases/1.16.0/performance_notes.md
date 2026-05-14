# SmarterCSV 1.16.0 — Performance Notes

Measured on Apple M1 Pro, Ruby 3.4.7, best of two benchmark sessions (30 runs each).
See [benchmarks.md](benchmarks.md) for full tables.

---

## vs Ruby CSV

### vs CSV.read (raw tokenization only — no hashes, no post-processing)

`CSV.read` is the *fastest* Ruby CSV mode. It returns plain string arrays with no header
handling, no symbol keys, no numeric conversion. SmarterCSV/C delivers fully processed
hashes — and still beats it on every single file:

| Range        | Files                                                              |
|--------------|--------------------------------------------------------------------|
| **8–9×**     | PEOPLE_IMPORT_C (8.1×), uszips (8.6×)                             |
| **6–7×**     | uscities (6.4×), worldcities (6.3×), embedded_sep (6.0×)          |
| **4–5×**     | PEOPLE_IMPORT_NC (4.8×), long_fields (5.5×), many_empty (5.2×), sample_10M (4.3×), utf8 (4.3×) |
| **3×**       | heavy_quoting (3.1×), tab_sep (3.3×), whitespace (3.1×), embedded_newlines (2.8×) |
| **2–3×**     | PEOPLE_IMPORT_B (2.9×), PEOPLE_IMPORT_NB (2.7×), sensor_data (2.2×), multi_char (2.4×) |
| **~1.7×**    | wide_500_cols (1.7×) — most column-heavy file, hash overhead visible |

**Summary: 1.7×–8.6× faster than CSV.read, while returning fully processed hashes.**

### vs CSV.table (symbol keys + numeric conversion — nearest equivalent output)

`CSV.table` is the fairest apples-to-apples comparison: it also produces symbol-keyed
rows with type conversion applied. SmarterCSV/C is dramatically faster:

| Range          | Files                                                           |
|----------------|-----------------------------------------------------------------|
| **100×+**      | PEOPLE_IMPORT_C (129×)                                          |
| **40–50×**     | PEOPLE_IMPORT_NC (48×), many_empty (46×), wide_500_cols (41×)  |
| **20–30×**     | PEOPLE_IMPORT_B (24×), PEOPLE_IMPORT_NB (26×), uszips (28×), tab_sep (27×), whitespace (24×), sensor_data (24×), utf8 (23×), multi_char (20×), worldcities (20×), sample_10M (20×) |
| **15–20×**     | uscities (21×), long_fields (16×), heavy_quoting (19×), embedded_sep (20×) |
| **7×**         | embedded_newlines (7×) — multiline rows, overhead unavoidable   |

**Summary: 7×–129× faster than CSV.table.**

---

## vs SmarterCSV 1.15.2

### C path

| Gain         | Files                                                                       |
|--------------|-----------------------------------------------------------------------------|
| **2.4×**     | long_fields — biggest win; `memchr` skip-ahead in quoted fields             |
| **1.5×**     | heavy_quoting — same skip-ahead benefit                                     |
| **1.4×**     | tab_separated                                                               |
| **1.2–1.3×** | embedded_sep, utf8, PEOPLE_IMPORT_C/NC, worldcities, whitespace, multi_char |
| **1.1–1.2×** | PEOPLE_IMPORT_B/NB, uszips, sample_10M, wide_500_cols                       |
| **~1.0×**    | sensor_data, embedded_newlines (within noise)                               |

15 of 19 files are measurably faster; 2 within noise; 2 files show a small regression
(PEOPLE_IMPORT_NB −7%, wide_500_cols −5%) attributable to the new `quote_boundary: :standard`
default adding one extra state check on the unquoted fast path.

### Ruby path

| Gain         | Files                                                                             |
|--------------|-----------------------------------------------------------------------------------|
| **1.9×**     | PEOPLE_IMPORT_C (117 cols) — direct hash construction bypasses intermediate Array |
| **1.5×**     | PEOPLE_IMPORT_NC, multi_char_sep                                                  |
| **1.0–1.1×** | most other files                                                                  |

The Ruby path gains are concentrated on wide/complex files where the direct-hash
construction optimization (Opt #11) has the most impact.

---

## vs SmarterCSV 1.14.4

C path is **9×–65× faster** across all 19 benchmark files:

- Long fields: **65×** (v1.15.0 introduced `memchr` skip-ahead)
- PEOPLE_IMPORT_C: **48×** (117 cols × 50k rows)
- PEOPLE_IMPORT_NC, multi_char_sep: **~21–24×**
- Typical real-world file: **10–20×**
- Minimum: **9.8×** (uscities, embedded_newlines)

---

## vs ZSV (C library, GC disabled)

ZSV is a dedicated C CSV library with GC disabled during measurement (working around a
bug in zsv-ruby 1.3.1 on Ruby 3.4.x). Despite this advantage:

**SmarterCSV/C beats ZSV+wrapper** (the fair comparison — both return processed hashes)
on 18 of 19 files, by **2–7×**. ZSV+wrapper is faster only on `embedded_newlines`
(1.5×), where ZSV's chunked I/O is particularly efficient.

**SmarterCSV/C vs ZSV.read** (raw arrays, GC disabled): ZSV.read is faster on most files
(2–12×), which is expected — it does far less work and has GC disabled. SmarterCSV/C
matches or beats ZSV.read on PEOPLE_IMPORT_C (the 117-column file) and PEOPLE_IMPORT_NC,
where our C hash-building overhead is proportionally small.

---

## column_selection speedup (`headers: { only: }`)

When using `headers: { only: [...] }` to select a subset of columns, excluded columns
are skipped entirely in the C hot path — no string allocation, no conversion, no hash
insertion. Benchmark on `wide_500_cols_20k.csv` (500 columns):

| Columns kept | Speedup vs no selection |
|--------------|-------------------------|
|    2 of 500  |             ~16× faster |
|   10 of 500  |             ~8× faster  |
|   50 of 500  |             ~3× faster  |

This is additive on top of the baseline gains above.
