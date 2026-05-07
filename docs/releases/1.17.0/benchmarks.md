# SmarterCSV 1.17.0 — Benchmark Results

- **Date:** 2026-05-06
- **Ruby:** 3.4.7 [arm64-darwin25] on Apple M1 Pro
- **SmarterCSV:** 1.17.0
- **Versions compared:** 1.14.4, 1.15.2, 1.16.4, 1.17.0
- **Ruby CSV:** 3.3.5
- **Methodology:** best of 40 measured runs (2 warm-up)
- **Raw data files:**
  - [`2026-05-06_1250_ruby3.4.7.md`](2026-05-06_1250_ruby3.4.7.md) / [`.json`](2026-05-06_1250_ruby3.4.7.json) — version comparison (1.14.4 / 1.15.2 / 1.16.4 / 1.17.0)
  - [`2026-05-06_1511_ruby3.4.7.md`](2026-05-06_1511_ruby3.4.7.md) / [`.json`](2026-05-06_1511_ruby3.4.7.json) — vs Ruby CSV 3.3.5

See [performance_notes.md](performance_notes.md) for analysis of these numbers.

---

## SmarterCSV C accelerated — version comparison

| File                             |   Rows | v1.14.4    | v1.15.2   | v1.16.4   | v1.17.0   | newest vs oldest |
|----------------------------------|--------|------------|-----------|-----------|-----------|------------------|
| PEOPLE_IMPORT_B.csv              |  50000 |  1.6175s   |  0.1049s  |  0.0867s  |  0.0872s  | 18.54× faster    |
| PEOPLE_IMPORT_C.csv              |  50000 |  8.0347s   |  0.2055s  |  0.1763s  |  0.1746s  | 46.02× faster    |
| PEOPLE_IMPORT_NB.csv             |  50000 |  1.5629s   |  0.0994s  |  0.0694s  |  0.0708s  | 22.08× faster    |
| PEOPLE_IMPORT_NC.csv             |  50000 |  1.4679s   |  0.0855s  |  0.0711s  |  0.0705s  | 20.83× faster    |
| uscities.csv                     |  31257 |  1.0357s   |  0.1129s  |  0.0878s  |  0.0819s  | 12.64× faster    |
| uszips.csv                       |  33782 |  1.2419s   |  0.1121s  |  0.0880s  |  0.0879s  | 14.13× faster    |
| worldcities.csv                  |  48059 |  1.0420s   |  0.1174s  |  0.0861s  |  0.0773s  | 13.49× faster    |
| embedded_newlines_20k.csv        |  80000 |  0.5337s   |  0.0633s  |  0.0591s  |  0.0545s  |  9.80× faster    |
| embedded_separators_20k.csv      |  20000 |  0.2761s   |  0.0328s  |  0.0215s  |  0.0214s  | 12.90× faster    |
| heavy_quoting_20k.csv            |  20000 |  0.5129s   |  0.0561s  |  0.0364s  |  0.0358s  | 14.34× faster    |
| long_fields_20k.csv              |  20000 |  2.9215s   |  0.1082s  |  0.0464s  |  0.0392s  | 74.54× faster    |
| many_empty_fields_20k.csv        |  20000 |  0.3885s   |  0.0314s  |  0.0240s  |  0.0262s  | 14.81× faster    |
| multi_char_separator_20k.csv     |  20000 |  0.5305s   |  0.0340s  |  0.0272s  |  0.0296s  | 17.90× faster    |
| sample_10M.csv                   |  50000 |  0.4513s   |  0.0619s  |  0.0480s  |  0.0446s  | 10.11× faster    |
| sensor_data_50krows_50cols.csv   |  50000 |  3.8704s   |  0.2714s  |  0.2559s  |  0.2549s  | 15.19× faster    |
| tab_separated_20k.tsv            |  20000 |  0.4496s   |  0.0337s  |  0.0255s  |  0.0256s  | 17.54× faster    |
| utf8_multibyte_20k.csv           |  20000 |  0.2233s   |  0.0210s  |  0.0152s  |  0.0149s  | 14.96× faster    |
| whitespace_heavy_20k.csv         |  20000 |  0.5244s   |  0.0349s  |  0.0250s  |  0.0286s  | 18.34× faster    |
| wide_500_cols_20k.csv            |  20000 | 17.3477s   |  1.2805s  |  1.2798s  |  1.2701s  | 13.66× faster    |

## SmarterCSV Ruby path — version comparison

| File                             |   Rows | v1.14.4    | v1.15.2   | v1.16.4   | v1.17.0   | newest vs oldest |
|----------------------------------|--------|------------|-----------|-----------|-----------|------------------|
| PEOPLE_IMPORT_B.csv              |  50000 |  4.5718s   |  0.5635s  |  0.5272s  |  0.4971s  |  9.20× faster    |
| PEOPLE_IMPORT_C.csv              |  50000 | 26.0194s   |  2.5511s  |  1.3401s  |  1.3328s  | 19.52× faster    |
| PEOPLE_IMPORT_NB.csv             |  50000 |  4.4999s   |  0.5268s  |  0.4757s  |  0.4791s  |  9.39× faster    |
| PEOPLE_IMPORT_NC.csv             |  50000 |  4.3233s   |  0.5752s  |  0.3989s  |  0.4017s  | 10.76× faster    |
| uscities.csv                     |  31257 |  2.6702s   |  1.8124s  |  1.0662s  |  1.0944s  |  2.44× faster    |
| uszips.csv                       |  33782 |  3.1853s   |  2.1641s  |  1.3332s  |  1.3434s  |  2.37× faster    |
| worldcities.csv                  |  48059 |  2.8397s   |  1.8978s  |  1.0910s  |  1.0909s  |  2.60× faster    |
| embedded_newlines_20k.csv        |  80000 |  0.9578s   |  0.4629s  |  0.4291s  |  0.4314s  |  2.22× faster    |
| embedded_separators_20k.csv      |  20000 |  0.7074s   |  0.4535s  |  0.2748s  |  0.2748s  |  2.57× faster    |
| heavy_quoting_20k.csv            |  20000 |  1.4361s   |  0.8598s  |  0.5241s  |  0.5273s  |  2.72× faster    |
| long_fields_20k.csv              |  20000 |  8.8715s   |  4.7839s  |  2.5696s  |  2.5624s  |  3.46× faster    |
| many_empty_fields_20k.csv        |  20000 |  0.8635s   |  0.2521s  |  0.1680s  |  0.1664s  |  5.19× faster    |
| multi_char_separator_20k.csv     |  20000 |  1.4172s   |  0.2463s  |  0.1853s  |  0.1879s  |  7.54× faster    |
| sample_10M.csv                   |  50000 |  1.0547s   |  0.2388s  |  0.2238s  |  0.2211s  |  4.77× faster    |
| sensor_data_50krows_50cols.csv   |  50000 |  8.9445s   |  1.8246s  |  1.8348s  |  1.8181s  |  4.92× faster    |
| tab_separated_20k.tsv            |  20000 |  1.2664s   |  0.1596s  |  0.1553s  |  0.1536s  |  8.24× faster    |
| utf8_multibyte_20k.csv           |  20000 |  0.6484s   |  0.1124s  |  0.1068s  |  0.1066s  |  6.08× faster    |
| whitespace_heavy_20k.csv         |  20000 |  1.5513s   |  0.1613s  |  0.1654s  |  0.1610s  |  9.63× faster    |
| wide_500_cols_20k.csv            |  20000 | 44.5782s   |  7.2023s  |  6.9748s  |  6.9261s  |  6.44× faster    |

---

## SmarterCSV 1.17.0 vs Ruby CSV 3.3.5 — full results

| File                             |   Rows | CSV.read¹  | CSV.hashes¹ | SmarterCSV/C  | SmarterCSV/Rb |
|----------------------------------|--------|------------|-------------|---------------|---------------|
| PEOPLE_IMPORT_B.csv              |  50000 |  0.2718s   |  0.7750s    |  0.0673s      |  0.5034s      |
| PEOPLE_IMPORT_C.csv              |  50000 |  1.4111s   |  8.0199s    |  0.1907s      |  1.4032s      |
| PEOPLE_IMPORT_NB.csv             |  50000 |  0.2659s   |  0.7603s    |  0.0638s      |  0.4800s      |
| PEOPLE_IMPORT_NC.csv             |  50000 |  0.2860s   |  0.9173s    |  0.0630s      |  0.4132s      |
| uscities.csv                     |  31257 |  0.5640s   |  0.8803s    |  0.0789s      |  1.1120s      |
| uszips.csv                       |  33782 |  0.7414s   |  1.1604s    |  0.0929s      |  1.3645s      |
| worldcities.csv                  |  48059 |  0.6313s   |  0.9906s    |  0.0794s      |  1.0945s      |
| embedded_newlines_20k.csv        |  80000 |  0.1693s   |  0.2245s    |  0.0554s      |  0.4451s      |
| embedded_separators_20k.csv      |  20000 |  0.1312s   |  0.1838s    |  0.0206s      |  0.2830s      |
| heavy_quoting_20k.csv            |  20000 |  0.1167s   |  0.2410s    |  0.0338s      |  0.5400s      |
| long_fields_20k.csv              |  20000 |  0.2373s   |  0.2762s    |  0.0392s      |  2.6172s      |
| many_empty_fields_20k.csv        |  20000 |  0.1145s   |  0.3622s    |  0.0216s      |  0.1727s      |
| multi_char_separator_20k.csv     |  20000 |  0.0890s   |  0.2122s    |  0.0293s      |  0.1662s      |
| sample_10M.csv                   |  50000 |  0.1685s   |  0.3012s    |  0.0357s      |  0.2361s      |
| sensor_data_50krows_50cols.csv   |  50000 |  0.5655s   |  2.6744s    |  0.2442s      |  1.8878s      |
| tab_separated_20k.tsv            |  20000 |  0.0832s   |  0.2029s    |  0.0219s      |  0.1651s      |
| utf8_multibyte_20k.csv           |  20000 |  0.0662s   |  0.1427s    |  0.0156s      |  0.1138s      |
| whitespace_heavy_20k.csv         |  20000 |  0.0890s   |  0.2169s    |  0.0278s      |  0.1670s      |
| wide_500_cols_20k.csv            |  20000 |  2.3351s   | 32.4002s    |  1.2823s      |  7.3504s      |

## Ruby CSV 3.3.5 vs SmarterCSV 1.17.0 (C accelerated)

| File                             |   Rows | CSV.read¹     | CSV.hashes¹   |
|----------------------------------|--------|---------------|---------------|
| PEOPLE_IMPORT_B.csv              |  50000 |  4.04× slower | 11.51× slower |
| PEOPLE_IMPORT_C.csv              |  50000 |  7.40× slower | 42.04× slower |
| PEOPLE_IMPORT_NB.csv             |  50000 |  4.17× slower | 11.92× slower |
| PEOPLE_IMPORT_NC.csv             |  50000 |  4.54× slower | 14.55× slower |
| uscities.csv                     |  31257 |  7.15× slower | 11.16× slower |
| uszips.csv                       |  33782 |  7.98× slower | 12.50× slower |
| worldcities.csv                  |  48059 |  7.95× slower | 12.48× slower |
| embedded_newlines_20k.csv        |  80000 |  3.05× slower |  4.05× slower |
| embedded_separators_20k.csv      |  20000 |  6.36× slower |  8.91× slower |
| heavy_quoting_20k.csv            |  20000 |  3.46× slower |  7.14× slower |
| long_fields_20k.csv              |  20000 |  6.05× slower |  7.04× slower |
| many_empty_fields_20k.csv        |  20000 |  5.29× slower | 16.73× slower |
| multi_char_separator_20k.csv     |  20000 |  3.04× slower |  7.25× slower |
| sample_10M.csv                   |  50000 |  4.72× slower |  8.43× slower |
| sensor_data_50krows_50cols.csv   |  50000 |  2.32× slower | 10.95× slower |
| tab_separated_20k.tsv            |  20000 |  3.80× slower |  9.28× slower |
| utf8_multibyte_20k.csv           |  20000 |  4.24× slower |  9.14× slower |
| whitespace_heavy_20k.csv         |  20000 |  3.20× slower |  7.81× slower |
| wide_500_cols_20k.csv            |  20000 |  1.82× slower | 25.27× slower |

---

¹ **Raw output** — no post-processing applied. Returns plain arrays or string-keyed hashes. No header normalization, type conversion, whitespace stripping, or empty-value removal. Your own post-processing must be added to produce usable data.

---

PREVIOUS: [Performance Notes](./performance_notes.md) | UP: [README](../../../README.md)
