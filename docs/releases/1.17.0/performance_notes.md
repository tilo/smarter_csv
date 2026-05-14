# SmarterCSV 1.17.0 — Performance Notes

The per-file tables below: Apple M4, Ruby 3.4.7 [arm64], 40 iterations per run × 8 runs, median across runs (p10-trimmed), measured 2026-05-11–12. 19-file corpus; `1.16.4 → 1.17.0`. Times in seconds — lower is better. (The "vs Ruby CSV" tables further down are from the earlier 2026-05-06 run — see Methodology.)

---

## 1.16.4 → 1.17.0 — C-accelerated path (the default)

The C parser's core line-parsing (separator splitting, quote/escape handling, multiline stitching) is unchanged from 1.16.0. The C-path changes this cycle are a faster code path for quoted-field-heavy files — the big wins — and Unicode-aware blank detection.

| file                           | 1.16.4 (s) | 1.17.0 (s) | 1.17.0 vs 1.16.4 |
| ------------------------------ | ---------- | ---------- | ---------------- |
| PEOPLE_IMPORT_B.csv            |    0.06255 |    0.06305 | ~1% noise        |
| PEOPLE_IMPORT_C.csv            |    0.13072 |    0.13274 | ~2% noise        |
| PEOPLE_IMPORT_NB.csv           |    0.05985 |    0.06079 | ~2% noise        |
| PEOPLE_IMPORT_NC.csv           |    0.05273 |    0.05420 | ~3% noise        |
| uscities.csv                   |    0.06325 |    0.05545 | 12.3% faster     |
| uszips.csv                     |    0.06957 |    0.06255 | 10.1% faster     |
| worldcities.csv                |    0.06824 |    0.06134 | 10.1% faster     |
| embedded_newlines_60k.csv      |    0.12795 |    0.11951 | 6.6% faster      |
| embedded_separators_60k.csv    |    0.05093 |    0.04591 | 9.9% faster      |
| heavy_quoting_60k.csv          |    0.08926 |    0.07490 | 16.1% faster     |
| long_fields_40k.csv            |    0.06375 |    0.04970 | 22.0% faster     |
| many_empty_fields_60k.csv      |    0.06813 |    0.06888 | ~1% noise        |
| multi_char_separator_60k.csv   |    0.07720 |    0.07830 | ~1% noise        |
| sample_100k.csv                |    0.07051 |    0.07139 | ~1% noise        |
| sensor_data_50krows_50cols.csv |    0.17839 |    0.17897 | ~1% noise        |
| tab_separated_60k.tsv          |    0.06704 |    0.06798 | ~1% noise        |
| utf8_multibyte_60k.csv         |    0.04391 |    0.04376 | ~ same           |
| whitespace_heavy_60k.csv       |    0.06803 |    0.06897 | ~1% noise        |
| wide_500_cols_20k.csv          |    1.07019 |    1.07348 | ~1% noise        |

*`~N% noise` means the measured difference (≈N%, always a small slowdown here) is within the run-to-run variance of this setup (8 runs × 40 iterations, median across runs, p10-trimmed) — i.e. effectively unchanged, not a real regression. The raw per-version times are in the table for the exact figure.*

Quote-heavy / large-field / wide files run **7–22% faster** than 1.16.4 (`long_fields_40k` 22%, `heavy_quoting_60k` 16%, the city files 10–12%, `embedded_separators` 10%, `embedded_newlines` 7%). Everything else is within ±3% of 1.16.4 — effectively unchanged. (The short-line / many-small-field files do show a small, *consistent* uptick at the bottom of that band, traceable to the larger default auto-detection scan window plus a tiny per-line overhead; if that matters for your workload, set `auto_row_sep_chars` lower. See [What's driving the mixed C-path picture](#whats-driving-the-mixed-c-path-picture) below.)

---

## 1.16.4 → 1.17.0 — Ruby fallback path (`acceleration: false`)

Faster on nearly every file this cycle, from three changes: in-place stripping in the no-quote split path, a first-byte fast-reject before numeric conversion, and per-row / per-value overhead removed from the hash transformations.

| file                           | 1.16.4 (s) | 1.17.0 (s) | 1.17.0 vs 1.16.4 |
| ------------------------------ | ---------- | ---------- | ---------------- |
| PEOPLE_IMPORT_B.csv            |    0.38220 |    0.35281 | 7.7% faster      |
| PEOPLE_IMPORT_C.csv            |    0.99047 |    0.95728 | 3.4% faster      |
| PEOPLE_IMPORT_NB.csv           |    0.36110 |    0.31716 | 12.2% faster     |
| PEOPLE_IMPORT_NC.csv           |    0.28762 |    0.25849 | 10.1% faster     |
| uscities.csv                   |    0.74246 |    0.71183 | 4.1% faster      |
| uszips.csv                     |    0.90817 |    0.87628 | 3.5% faster      |
| worldcities.csv                |    0.75714 |    0.72641 | 4.1% faster      |
| embedded_newlines_60k.csv      |    0.88887 |    0.86252 | 3.0% faster      |
| embedded_separators_60k.csv    |    0.57053 |    0.53401 | 6.4% faster      |
| heavy_quoting_60k.csv          |    1.09395 |    1.02829 | 6.0% faster      |
| long_fields_40k.csv            |    3.27964 |    3.29366 | ~ same           |
| many_empty_fields_60k.csv      |    0.37815 |    0.33153 | 12.3% faster     |
| multi_char_separator_60k.csv   |    0.45717 |    0.38380 | 16.0% faster     |
| sample_100k.csv                |    0.34527 |    0.30690 | 11.1% faster     |
| sensor_data_50krows_50cols.csv |    1.32705 |    1.33218 | ~ same           |
| tab_separated_60k.tsv          |    0.38261 |    0.31359 | 18.0% faster     |
| utf8_multibyte_60k.csv         |    0.24212 |    0.21281 | 12.1% faster     |
| whitespace_heavy_60k.csv       |    0.37635 |    0.30848 | 18.0% faster     |
| wide_500_cols_20k.csv          |    5.28395 |    4.23045 | 19.9% faster     |

Gains run **3–20%** vs 1.16.4, biggest on wide / many-small-field files (`wide_500_cols` 20%, `whitespace_heavy` / `tab_separated` 18%, `multi_char_separator` 16%). Only `long_fields_40k` (dominated by large-field allocation, not per-field work) and `sensor_data` (numeric-heavy — the fast-reject's per-value cost and a saved per-value method call cancel out) sit at parity.

---

## What's driving the mixed C-path picture

The C parser's core line-parsing — separator splitting, quote/escape handling, multiline stitching — is unchanged from 1.16.0; all of that hot-path work carries forward (see [the 1.16.0 changes](../1.16.0/changes.md) for the parser performance story). So why the split — some files faster, a band of small files a hair slower?

**The wins are the quoted-field handling.** 1.17.0 added a faster path for fields wrapped in quotes: the common case — a quoted field with no doubled `""` inside — now skips a copy step. Files where most or all fields are quoted (city/address-style data, long quoted text, wide rows) pick up 7–22%.

**The bigger default auto-detection window.** The benchmark leaves `row_sep` at `:auto` for every file, so each run reads `auto_row_sep_chars` bytes up front — now `4096`, was `500` — and scans them for the row separator.
  * On tiny files where total parse time is only ~50–80 ms, that one-time scan shows up as a ≤3% uptick.
  * On larger files it's noise (and often net-positive — the wider window usually settles the separator on the first read, avoiding the doubling-escalation loop).
If you parse lots of very small files and care about that 1–3%, set `auto_row_sep_chars` lower, or pin `row_sep` explicitly to skip detection entirely. (The related `guess_line_ending` change — a chunked scan that doubles up to a 64 KB hard cap, replacing the old undocumented "scan whole file" on `nil`/`0` — is the same trade-off.)

**Not a factor here:** the buffering layer for non-seekable streams. The benchmark passes file paths to `SmarterCSV.process`, which opens them as seekable `File` objects, so the seekable fast path is taken and no buffering wrapper is instantiated. That layer only runs for pipes / gzip readers / HTTP/S3 bodies, which have much higher latency anyway — any extra work the buffer does there is negligible.

---

## vs Ruby CSV 3.3.5 (1.17.0 reference)

### vs `CSV.read` (raw arrays — minimum equivalent work)

`CSV.read` is the *fastest* Ruby CSV mode: plain string arrays, no symbol keys, no numeric conversion. SmarterCSV/C delivers fully processed hashes — and still beats it on every file:

| Range     | Files                                                                   |
|-----------|-------------------------------------------------------------------------|
| **7–8×**  | PEOPLE_IMPORT_C (7.8×), uszips (7.8×)                                   |
| **6–7×**  | long_fields (6.9×), uscities (6.8×), worldcities (6.8×)                 |
| **5–6×**  | embedded_separators (5.4×)                                              |
| **3–4×**  | utf8_multibyte (3.9×), PEOPLE_IMPORT_NC (3.7×), many_empty (3.5×), heavy_quoting (3.4×), sample_100k (3.4×), PEOPLE_IMPORT_NB (3.2×) |
| **2–3×**  | PEOPLE_IMPORT_B (2.9×), embedded_newlines (2.9×), whitespace_heavy (2.9×), sensor_data (2.5×) |
| **1–2×**  | wide_500_cols (1.7×), tab_separated (1.6×), multi_char_separator (1.4×) |

**Summary: 1.4×–7.8× faster than `CSV.read`, while returning fully processed hashes.**

### vs `CSV.hashes` (string-keyed hashes — closer to SmarterCSV output)

| Range      | Files                                                                  |
|------------|------------------------------------------------------------------------|
| **40–50×** | PEOPLE_IMPORT_C (47.3×)                                                |
| **20–25×** | wide_500_cols (22.1×)                                                  |
| **10–15×** | uszips (12.5×), PEOPLE_IMPORT_NC (12.1×), many_empty (11.8×), worldcities (11.4×), uscities (11.2×), sensor_data (11.1×) |
| **7–10×**  | embedded_separators (8.3×), long_fields (8.1×), PEOPLE_IMPORT_NB (8.1×), PEOPLE_IMPORT_B (7.9×), heavy_quoting (7.0×) |
| **5–7×**   | whitespace_heavy (6.9×), utf8_multibyte (6.7×), sample_100k (6.2×)     |
| **4–5×**   | embedded_newlines (4.2×)                                               |
| **2–3×**   | tab_separated (2.3×), multi_char_separator (2.2×)                      |

**Summary: 2.2×–47.3× faster than `CSV.hashes`.**

---

## Methodology

Same as 1.16.0:
- Apple M4, Ruby 3.4.7
- 40 iterations per run × 8 runs (2 warm-up), median across runs (p10-trimmed)
- Raw .json captures preserved alongside the .md tables for reproducibility

---

PREVIOUS: [Changes](./changes.md) | UP: [README](../../../README.md)
