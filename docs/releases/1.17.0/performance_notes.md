# SmarterCSV 1.17.0 — Performance Notes

Measured on Apple M1 Pro, Ruby 3.4.7, best of 40 runs (2 warm-up). Same 19-file corpus as the 1.16.0 benchmarks, for direct comparability.

Raw data: [`2026-05-06_1250_ruby3.4.7.md`](2026-05-06_1250_ruby3.4.7.md) (version comparison) and [`2026-05-06_1511_ruby3.4.7.md`](2026-05-06_1511_ruby3.4.7.md) (vs Ruby CSV 3.3.5).

---

## 1.16.4 → 1.17.0 (C-accelerated path)

### Measurably faster (>5%)

| File                      | 1.16.4   | 1.17.0   | Change          |
|---------------------------|----------|----------|-----------------|
| long_fields_20k.csv       | 0.0464s  | 0.0392s  | **−15.5%**      |
| worldcities.csv           | 0.0861s  | 0.0773s  | **−10.2%**      |
| embedded_newlines_20k.csv | 0.0591s  | 0.0545s  | **−7.8%**       |
| sample_10M.csv            | 0.0480s  | 0.0446s  | **−7.1%**       |
| uscities.csv              | 0.0878s  | 0.0819s  | **−6.7%**       |

### Measurably slower (>5%)

| File                          | 1.16.4   | 1.17.0   | Change          |
|-------------------------------|----------|----------|-----------------|
| whitespace_heavy_20k.csv      | 0.0250s  | 0.0286s  | **+14.4%**      |
| many_empty_fields_20k.csv     | 0.0240s  | 0.0262s  | **+9.2%**       |
| multi_char_separator_20k.csv  | 0.0272s  | 0.0296s  | **+8.8%**       |

### Within noise (±5%)

11 files: PEOPLE_IMPORT_B/C/NB/NC, uszips, embedded_separators, heavy_quoting, sensor_data, tab_separated, utf8_multibyte, wide_500_cols.

---

## 1.16.4 → 1.17.0 (Ruby path)

Largely flat — only PEOPLE_IMPORT_B shows a measurable gain (**−5.7%**, 0.5272s → 0.4971s). All other files are within noise. The Ruby path doesn't share the C path's small-file regression pattern, because it is generally slower, and the small fixed cost for a more thorrough auto-detection does not show as much.
---

## What's driving the mixed C-path picture

The C parser hot path was not modified in 1.17.0. All 1.16.0 optimizations carry forward:

- ParseContext architecture
- Column-filter bitmap (`headers: { only: }` early exit)
- Section 4 fast-path split (plain unquoted vs. boundary-aware `:standard`)
- Byte-level indexing (`getbyte`, `byteslice`, `memchr` skip-ahead)
- `-fno-semantic-interposition`, `cold`/`hot` attributes

**Dominant factor: `auto_row_sep_chars` default `500` → `8192`** — the auto-detection scan window is now 16× larger by default. The benchmark config leaves `row_sep` at `:auto` for every file, so every run reads ~7 KB up front (vs ~500 bytes before) and runs the row-separator scan over it. On small / fast files where total parse time is 25–30 ms, that one-time cost shows up as a 5–15% slowdown. On larger files where parse time dominates, the same change is invisible or even net-positive — the wider window often finds a clear majority on the first chunk, avoiding the chunk-grow loop that 1.16.4 sometimes paid.

A related change — **`guess_line_ending` chunked scan with 64KB hard cap** — replaces the previous undocumented "scan whole file" behavior on `nil`/`0`. Same code path; tied to the same trade-off.

The gains and regressions are both consistent with this single cause: files with long lines / lots of work per row absorb the wider scan cost easily; files with short lines / minimal work per row see the cost more visibly.

**Not a factor on these benchmarks:** the buffering layer that supports non-seekable streams. The benchmark adapter passes file paths to `SmarterCSV.process`, which opens them as seekable `File` objects. The seekable-input fast path is taken and no buffering wrapper is instantiated (verified by inspection of `Reader#process` — `seekable?(fh)` returns true for `File`, so the wrapping branch is skipped). The buffering layer only runs for non-seekable inputs (pipes, gzip readers, HTTP/S3 bodies) which aren't part of this benchmark suite.

---

## vs Ruby CSV 3.3.5 (1.17.0 reference)

Speedup tables from [`2026-05-06_1511_ruby3.4.7.md`](2026-05-06_1511_ruby3.4.7.md):

### vs `CSV.read` (raw arrays — minimum equivalent work)

`CSV.read` is the *fastest* Ruby CSV mode: plain string arrays, no symbol keys, no numeric conversion. SmarterCSV/C delivers fully processed hashes — and still beats it on every file:

| Range     | Files                                                                   |
|-----------|-------------------------------------------------------------------------|
| **8–9×**  | PEOPLE_IMPORT_C (7.4×), uszips (8.0×), worldcities (8.0×)               |
| **6–7×**  | uscities (7.1×), embedded_separators (6.4×), long_fields (6.0×)         |
| **4–5×**  | PEOPLE_IMPORT_B/NB (4.0–4.2×), PEOPLE_IMPORT_NC (4.5×), many_empty (5.3×), sample_10M (4.7×), utf8 (4.2×) |
| **3×**    | heavy_quoting (3.5×), tab_sep (3.8×), whitespace (3.2×), embedded_newlines (3.1×), multi_char (3.0×) |
| **2–3×**  | sensor_data (2.3×), wide_500_cols (1.8×)                                |

**Summary: 1.8×–8.0× faster than `CSV.read`, while returning fully processed hashes.**

### vs `CSV.hashes` (string-keyed hashes — closer to SmarterCSV output)

| Range      | Files                                                                  |
|------------|------------------------------------------------------------------------|
| **40–45×** | PEOPLE_IMPORT_C (42.0×)                                                |
| **20–30×** | wide_500_cols (25.3×), many_empty (16.7×)                              |
| **10–15×** | most files: PEOPLE_IMPORT_B/NB/NC, uscities, uszips, worldcities, sensor_data, etc. |
| **7–10×**  | embedded_newlines (4.0×), embedded_sep (8.9×), long_fields (7.0×), heavy_quoting (7.1×), multi_char (7.3×) |

**Summary: 4×–42× faster than `CSV.hashes`.**

---

## Charts

- **Comparison of Versions: C path** — [`2026-05-06_1250_ruby3.4.7_versions_chart_C-path.svg`](2026-05-06_1250_ruby3.4.7_versions_chart_C-path.svg)
- **Comparison of Versions: Ruby path** — [`2026-05-06_1250_ruby3.4.7_versions_chart_Ruby-path.svg`](2026-05-06_1250_ruby3.4.7_versions_chart_Ruby-path.svg)
- **Speedup of SmarterCSV vs Ruby CSV** — [`2026-05-06_1511_ruby3.4.7_speedup_chart.svg`](2026-05-06_1511_ruby3.4.7_speedup_chart.svg)

---

## Methodology

Same as 1.16.0:
- Apple M1 Pro, Ruby 3.4.7
- Best of 40 measured runs (2 warm-up)
- Raw .json captures preserved alongside the .md tables for reproducibility

---

PREVIOUS: [Changes](./changes.md) | UP: [README](../../../README.md)
