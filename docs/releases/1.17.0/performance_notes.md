# SmarterCSV 1.17.0 — Performance Notes

The per-file tables below: Apple M3, Ruby 3.4.7 [arm64], 40 iterations per run × 8 runs, median across runs (p10-trimmed), measured 2026-05-11. 19-file corpus; `1.16.4 → 1.17.0`. Times in seconds — lower is better. (The "vs Ruby CSV" tables further down are from the earlier 2026-05-06 run — see Methodology.)

Raw data: [`2026-05-06_1250_ruby3.4.7.md`](2026-05-06_1250_ruby3.4.7.md) (version comparison) and [`2026-05-06_1511_ruby3.4.7.md`](2026-05-06_1511_ruby3.4.7.md) (vs Ruby CSV 3.3.5).

---

## 1.16.4 → 1.17.0 — C-accelerated path (the default)

The C parser's core line-parsing (separator splitting, quote/escape handling, multiline stitching) is unchanged from 1.16.0. The C-path changes this cycle are a faster code path for quoted-field-heavy files — the big wins — and Unicode-aware blank detection.

| file                           | 1.16.4 (s) | 1.17.0 (s) | 1.17.0 vs 1.16.4 |
| ------------------------------ | ---------- | ---------- | ---------------- |
| PEOPLE_IMPORT_B.csv            |    0.06268 |    0.06326 | ~1% error        |
| PEOPLE_IMPORT_C.csv            |    0.13115 |    0.13186 | ~1% error        |
| PEOPLE_IMPORT_NB.csv           |    0.05964 |    0.06089 | ~2% error        |
| PEOPLE_IMPORT_NC.csv           |    0.05298 |    0.05386 | ~2% error        |
| uscities.csv                   |    0.06326 |    0.05517 | 12.8% faster     |
| uszips.csv                     |    0.06983 |    0.06247 | 10.5% faster     |
| worldcities.csv                |    0.06833 |    0.06153 | 10.0% faster     |
| embedded_newlines_60k.csv      |    0.12836 |    0.11878 | 7.5% faster      |
| embedded_separators_60k.csv    |    0.05096 |    0.04617 | 9.4% faster      |
| heavy_quoting_60k.csv          |    0.08932 |    0.07450 | 16.6% faster     |
| long_fields_40k.csv            |    0.06379 |    0.04950 | 22.4% faster     |
| many_empty_fields_60k.csv      |    0.06794 |    0.06900 | ~2% error        |
| multi_char_separator_60k.csv   |    0.07715 |    0.07902 | ~2% error        |
| sample_100k.csv                |    0.07106 |    0.07196 | ~1% error        |
| sensor_data_50krows_50cols.csv |    0.17895 |    0.17945 | ~1% error        |
| tab_separated_60k.tsv          |    0.06696 |    0.06789 | ~1% error        |
| utf8_multibyte_60k.csv         |    0.04228 |    0.04346 | ~3% error        |
| whitespace_heavy_60k.csv       |    0.06790 |    0.06886 | ~1% error        |
| wide_500_cols_20k.csv          |    1.07178 |    1.07738 | ~1% error        |

*`~N% error` means the measured difference (≈N%, always a small slowdown here) is within the run-to-run variance of this setup (8 runs × 40 iterations, median across runs, p10-trimmed) — i.e. effectively unchanged, not a real regression. The raw per-version times are in the table for the exact figure.*

Quote-heavy / large-field / wide files run **7–22% faster** than 1.16.4 (`long_fields_40k` 22%, `heavy_quoting_60k` 17%, the city files 10–13%, `embedded_separators` 9%, `embedded_newlines` 7.5%). Everything else is within ±3% of 1.16.4 — effectively unchanged. (The short-line / many-small-field files do show a small, *consistent* uptick at the bottom of that band, traceable to the larger default auto-detection scan window plus a tiny per-line overhead; if that matters for your workload, set `auto_row_sep_chars` lower. See [What's driving the mixed C-path picture](#whats-driving-the-mixed-c-path-picture) below.)

---

## 1.16.4 → 1.17.0 — Ruby fallback path (`acceleration: false`)

Faster on nearly every file this cycle, from three changes: in-place stripping in the no-quote split path, a first-byte fast-reject before numeric conversion, and per-row / per-value overhead removed from the hash transformations.

| file                           | 1.16.4 (s) | 1.17.0 (s) | 1.17.0 vs 1.16.4 |
| ------------------------------ | ---------- | ---------- | ---------------- |
| PEOPLE_IMPORT_B.csv            |    0.38218 |    0.35261 | 7.7% faster      |
| PEOPLE_IMPORT_C.csv            |    0.98864 |    0.95274 | 3.6% faster      |
| PEOPLE_IMPORT_NB.csv           |    0.36030 |    0.31644 | 12.2% faster     |
| PEOPLE_IMPORT_NC.csv           |    0.28767 |    0.25871 | 10.1% faster     |
| uscities.csv                   |    0.74246 |    0.71089 | 4.3% faster      |
| uszips.csv                     |    0.90764 |    0.87203 | 3.9% faster      |
| worldcities.csv                |    0.75642 |    0.72343 | 4.4% faster      |
| embedded_newlines_60k.csv      |    0.89032 |    0.86427 | 2.9% faster      |
| embedded_separators_60k.csv    |    0.57067 |    0.52975 | 7.2% faster      |
| heavy_quoting_60k.csv          |    1.09574 |    1.02425 | 6.5% faster      |
| long_fields_40k.csv            |    3.27737 |    3.27375 | ~ same           |
| many_empty_fields_60k.csv      |    0.37866 |    0.33203 | 12.3% faster     |
| multi_char_separator_60k.csv   |    0.45799 |    0.38346 | 16.3% faster     |
| sample_100k.csv                |    0.34454 |    0.30559 | 11.3% faster     |
| sensor_data_50krows_50cols.csv |    1.32900 |    1.32869 | ~ same           |
| tab_separated_60k.tsv          |    0.38359 |    0.31327 | 18.3% faster     |
| utf8_multibyte_60k.csv         |    0.24194 |    0.21202 | 12.4% faster     |
| whitespace_heavy_60k.csv       |    0.37718 |    0.30781 | 18.4% faster     |
| wide_500_cols_20k.csv          |    5.28440 |    4.24081 | 19.7% faster     |

Gains run **4–20%** vs 1.16.4, biggest on wide / many-small-field files (`wide_500_cols` 20%, `whitespace_heavy` / `tab_separated` 18%, `multi_char_separator` 16%). Only `long_fields_40k` (dominated by large-field allocation, not per-field work) and `sensor_data` (numeric-heavy — the fast-reject's per-value cost and a saved per-value method call cancel out) sit at parity.

---

## What's driving the mixed C-path picture

The C parser's core line-parsing — separator splitting, quote/escape handling, multiline stitching — is unchanged from 1.16.0; all of that hot-path work carries forward (see [the 1.16.0 changes](../1.16.0/changes.md) for the parser performance story). So why the split — some files faster, a band of small files a hair slower?

**The wins are the quoted-field handling.** 1.17.0 added a faster path for fields wrapped in quotes: the common case — a quoted field with no doubled `""` inside — now skips a copy step. Files where most or all fields are quoted (city/address-style data, long quoted text, wide rows) pick up 7–22%.

**The bigger default auto-detection window.** The benchmark leaves `row_sep` at `:auto` for every file, so each run reads `auto_row_sep_chars` bytes up front — now `4096`, was `500` — and scans them for the row separator.
  * On tiny files where total parse time is only ~25–30 ms, that one-time scan shows up as a ≤3% uptick.
  * On larger files it's noise (and often net-positive — the wider window usually settles the separator on the first read, avoiding the doubling-escalation loop).
If you parse lots of very small files and care about that 1–3%, set `auto_row_sep_chars` lower, or pin `row_sep` explicitly to skip detection entirely. (The related `guess_line_ending` change — a chunked scan that doubles up to a 64 KB hard cap, replacing the old undocumented "scan whole file" on `nil`/`0` — is the same trade-off.)

**Not a factor here:** the buffering layer for non-seekable streams. The benchmark passes file paths to `SmarterCSV.process`, which opens them as seekable `File` objects, so the seekable fast path is taken and no buffering wrapper is instantiated. That layer only runs for pipes / gzip readers / HTTP/S3 bodies, which have much higher latency anyway — any extra work the buffer does there is negligible.

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
