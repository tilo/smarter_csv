# SmarterCSV 1.16.0 — Benchmark Results

- **Date:** 2026-03-11 (two runs, best of each taken)
- **Ruby:** 3.4.7 [arm64-darwin25] on Apple M1 Pro
- **SmarterCSV:** 1.16.0.dev10
- **Versions compared:** 1.14.4, 1.15.0, 1.15.2, 1.16.0
- **Ruby CSV:** 3.3.5
- **ZSV:** 1.3.1
- **Methodology:** best of 30 measured runs (2 warm-up), best result taken across two independent sessions

> **Note:** ZSV results have GC disabled during calls (zsv-ruby 1.3.1 GC bug on Ruby 3.4.x).
> This gives ZSV a slight speed advantage — no GC pauses during measurement.

---

## SmarterCSV C accelerated — version comparison

| File                                 |    Rows |       v1.14.4 |       v1.15.0 |       v1.15.2 | v1.16.0       | newest vs oldest |
|--------------------------------------|---------|---------------|---------------|---------------|---------------|------------------|
| PEOPLE_IMPORT_B.csv                  |   50000 |       1.6556s |       0.3952s |       0.1012s |       0.0869s | 19.05× faster |
| PEOPLE_IMPORT_C.csv                  |   50000 |       8.1715s |       1.9714s |       0.2065s |       0.1691s | 48.32× faster |
| PEOPLE_IMPORT_NB.csv                 |   50000 |       1.6053s |       0.6043s |       0.0859s |       0.0799s | 20.09× faster |
| PEOPLE_IMPORT_NC.csv                 |   50000 |       1.4952s |       0.6202s |       0.0763s |       0.0630s | 23.73× faster |
| uscities.csv                         |   31257 |       1.0576s |       0.3395s |       0.1126s |       0.1079s |  9.80× faster |
| uszips.csv                           |   33782 |       1.2769s |       0.4532s |       0.1113s |       0.1019s | 12.53× faster |
| worldcities.csv                      |   48059 |       1.0703s |       0.4362s |       0.1160s |       0.0973s | 11.00× faster |
| embedded_newlines_20k.csv            |   80000 |       0.5404s |       0.0962s |       0.0564s |       0.0543s |  9.95× faster |
| embedded_separators_20k.csv          |   20000 |       0.2779s |       0.0831s |       0.0320s |       0.0248s | 11.21× faster |
| heavy_quoting_20k.csv                |   20000 |       0.5222s |       0.1330s |       0.0540s |       0.0359s | 14.55× faster |
| long_fields_20k.csv                  |   20000 |       2.9604s |       0.1357s |       0.1101s |       0.0451s | 65.64× faster |
| many_empty_fields_20k.csv            |   20000 |       0.3946s |       0.3787s |       0.0313s |       0.0251s | 15.72× faster |
| multi_char_separator_20k.csv         |   20000 |       0.5390s |       0.5452s |       0.0328s |       0.0260s | 20.73× faster |
| sample_10M.csv                       |   50000 |       0.4593s |       0.1642s |       0.0534s |       0.0461s |  9.96× faster |
| sensor_data_50krows_50cols.csv       |   50000 |       3.9848s |       1.4278s |       0.2722s |       0.2640s | 15.09× faster |
| tab_separated_20k.tsv                |   20000 |       0.4618s |       0.1111s |       0.0343s |       0.0245s | 18.85× faster |
| utf8_multibyte_20k.csv               |   20000 |       0.2276s |       0.0688s |       0.0204s |       0.0167s | 13.63× faster |
| whitespace_heavy_20k.csv             |   20000 |       0.5360s |       0.1206s |       0.0355s |       0.0281s | 19.07× faster |
| wide_500_cols_20k.csv                |   20000 |      17.6581s |       5.2151s |       1.4185s |       1.3519s | 13.06× faster |

## SmarterCSV Ruby path — version comparison

| File                                 |    Rows |       v1.14.4 |       v1.15.0 |       v1.15.2 | v1.16.0       | newest vs oldest |
|--------------------------------------|---------|---------------|---------------|---------------|---------------|------------------|
| PEOPLE_IMPORT_B.csv                  |   50000 |       4.6704s |       3.6190s |       0.5382s |       0.5174s |  9.03× faster |
| PEOPLE_IMPORT_C.csv                  |   50000 |      26.6781s |      22.8627s |       2.5588s |       1.3184s | 20.24× faster |
| PEOPLE_IMPORT_NB.csv                 |   50000 |       4.6031s |       3.5647s |       0.5325s |       0.4649s |  9.90× faster |
| PEOPLE_IMPORT_NC.csv                 |   50000 |       4.4299s |       3.7989s |       0.5843s |       0.3963s | 11.18× faster |
| uscities.csv                         |   31257 |       2.7374s |       2.1679s |       1.8397s |       1.0811s |  2.53× faster |
| uszips.csv                           |   33782 |       3.2771s |       2.6214s |       2.1987s |       1.3326s |  2.46× faster |
| worldcities.csv                      |   48059 |       2.8980s |       2.3094s |       1.9354s |       1.0869s |  2.67× faster |
| embedded_newlines_20k.csv            |   80000 |       0.9685s |       0.5729s |       0.4696s |       0.4275s |  2.27× faster |
| embedded_separators_20k.csv          |   20000 |       0.7177s |       0.5696s |       0.4620s |       0.2725s |  2.63× faster |
| heavy_quoting_20k.csv                |   20000 |       1.4473s |       1.1282s |       0.8769s |       0.5295s |  2.73× faster |
| long_fields_20k.csv                  |   20000 |       9.0238s |       6.4373s |       4.8163s |       2.5469s |  3.54× faster |
| many_empty_fields_20k.csv            |   20000 |       0.8739s |       0.7527s |       0.2603s |       0.1652s |  5.29× faster |
| multi_char_separator_20k.csv         |   20000 |       1.4261s |       1.1569s |       0.2457s |       0.1645s |  8.67× faster |
| sample_10M.csv                       |   50000 |       1.0699s |       0.8684s |       0.2419s |       0.2220s |  4.82× faster |
| sensor_data_50krows_50cols.csv       |   50000 |       9.2662s |       6.8954s |       1.8555s |       1.8147s |  5.11× faster |
| tab_separated_20k.tsv                |   20000 |       1.2786s |       0.9850s |       0.1620s |       0.1551s |  8.24× faster |
| utf8_multibyte_20k.csv               |   20000 |       0.6595s |       0.5650s |       0.1154s |       0.1054s |  6.26× faster |
| whitespace_heavy_20k.csv             |   20000 |       1.5723s |       1.2288s |       0.1684s |       0.1555s | 10.11× faster |
| wide_500_cols_20k.csv                |   20000 |      45.2838s |      34.7364s |       7.2952s |       6.9952s |  6.47× faster |

---

## Full Results — all adapters (seconds, best of 2 sessions × 30 runs)

| File                                 |    Rows | CSV.read¹     | CSV.hashes¹   | CSV.table²    | SmarterCSV/C  | SmarterCSV/Rb | ZSV.read¹     | ZSV+wrapper²  |
|--------------------------------------|---------|---------------|---------------|---------------|---------------|---------------|---------------|---------------|
| PEOPLE_IMPORT_B.csv                  |   50000 |       0.2537s |       0.7059s |       2.1440s |       0.0887s |       0.4895s |       0.0323s |       0.2380s |
| PEOPLE_IMPORT_C.csv                  |   50000 |       1.4265s |       8.1133s |      22.6230s |       0.1755s |       1.3401s |       0.2209s |       1.2759s |
| PEOPLE_IMPORT_NB.csv                 |   50000 |       0.2241s |       0.7087s |       2.2152s |       0.0838s |       0.4749s |       0.0312s |       0.2429s |
| PEOPLE_IMPORT_NC.csv                 |   50000 |       0.2847s |       0.8949s |       2.8887s |       0.0598s |       0.4015s |       0.0367s |       0.2192s |
| uscities.csv                         |   31257 |       0.5273s |       0.8796s |       1.7620s |       0.0830s |       1.0875s |       0.0244s |       0.2227s |
| uszips.csv                           |   33782 |       0.6994s |       1.1180s |       2.2444s |       0.0814s |       1.3326s |       0.0299s |       0.2448s |
| worldcities.csv                      |   48059 |       0.6033s |       0.9531s |       1.9404s |       0.0965s |       1.0869s |       0.0262s |       0.2125s |
| embedded_newlines_20k.csv            |   80000 |       0.1511s |       0.2185s |       0.3908s |       0.0545s |       0.4275s |       0.0045s |       0.0373s |
| embedded_separators_20k.csv          |   20000 |       0.1187s |       0.1769s |       0.3856s |       0.0197s |       0.2725s |       0.0051s |       0.0467s |
| heavy_quoting_20k.csv                |   20000 |       0.1128s |       0.2315s |       0.6996s |       0.0367s |       0.5295s |       0.0096s |       0.0740s |
| long_fields_20k.csv                  |   20000 |       0.2411s |       0.2812s |       0.6809s |       0.0437s |       2.5469s |       0.0255s |       0.0528s |
| many_empty_fields_20k.csv            |   20000 |       0.1075s |       0.3515s |       0.9626s |       0.0208s |       0.1652s |       0.0145s |       0.0740s |
| multi_char_separator_20k.csv         |   20000 |       0.0790s |       0.1946s |       0.6649s |       0.0334s |       0.1645s |           N/A |           N/A |
| sample_10M.csv                       |   50000 |       0.1506s |       0.2846s |       0.7051s |       0.0347s |       0.2220s |       0.0095s |       0.0759s |
| sensor_data_50krows_50cols.csv       |   50000 |       0.5643s |       2.6419s |       6.2180s |       0.2587s |       1.8147s |       0.0946s |       1.2241s |
| tab_separated_20k.tsv                |   20000 |       0.0805s |       0.2009s |       0.6594s |       0.0244s |       0.1571s |       0.0094s |       0.0740s |
| utf8_multibyte_20k.csv               |   20000 |       0.0638s |       0.1253s |       0.3405s |       0.0150s |       0.1054s |       0.0050s |       0.0420s |
| whitespace_heavy_20k.csv             |   20000 |       0.0897s |       0.2035s |       0.7104s |       0.0294s |       0.1555s |       0.0111s |       0.0834s |
| wide_500_cols_20k.csv                |   20000 |       2.4090s |      32.2438s |      57.6183s |       1.3898s |       6.9952s |       0.3565s |       4.6425s |

---

## Throughput (rows/second) — SmarterCSV 1.16.0 (C accelerated)

Higher is better.

| File                                 |    Rows | CSV.read¹     | CSV.hashes¹   | CSV.table²    | SmarterCSV/C  | SmarterCSV/Rb | ZSV.read¹     | ZSV+wrapper²  |
|--------------------------------------|---------|---------------|---------------|---------------|---------------|---------------|---------------|---------------|
| PEOPLE_IMPORT_B.csv                  |   50000 |        197087 |         70828 |         23321 |        563946 |         96638 |       1548001 |        210084 |
| PEOPLE_IMPORT_C.csv                  |   50000 |         35052 |          6163 |          2210 |        284899 |         37311 |        226347 |         39190 |
| PEOPLE_IMPORT_NB.csv                 |   50000 |        223123 |         70549 |         22571 |        596658 |        105270 |       1602564 |        205983 |
| PEOPLE_IMPORT_NC.csv                 |   50000 |        175620 |         55873 |         17309 |        835452 |        124535 |       1362398 |        228086 |
| uscities.csv                         |   31257 |         59277 |         35534 |         17740 |        376590 |         28741 |       1281148 |        140367 |
| uszips.csv                           |   33782 |         48298 |         30217 |         15051 |        415012 |         25351 |       1130399 |        138005 |
| worldcities.csv                      |   48059 |         79667 |         50423 |         24768 |        498016 |         44218 |       1833862 |        226161 |
| embedded_newlines_20k.csv            |   80000 |        529538 |        366143 |        204710 |       1467890 |        186709 |      17586283 |       2144255 |
| embedded_separators_20k.csv          |   20000 |        168462 |        113084 |         51872 |       1015228 |         73382 |       3921569 |        428265 |
| heavy_quoting_20k.csv                |   20000 |        176235 |         86408 |         28588 |        544796 |         37773 |       2088773 |        270270 |
| long_fields_20k.csv                  |   20000 |         82969 |         71112 |         29373 |        457666 |          7853 |        784314 |        378788 |
| many_empty_fields_20k.csv            |   20000 |        186043 |         56891 |         20776 |        961538 |        121068 |       1379310 |        270270 |
| multi_char_separator_20k.csv         |   20000 |        253165 |        102769 |         30082 |        598802 |        121618 |           N/A |           N/A |
| sample_10M.csv                       |   50000 |        331928 |        175694 |         70916 |       1441753 |        225225 |       5263158 |        658623 |
| sensor_data_50krows_50cols.csv       |   50000 |         88607 |         18926 |          8041 |        193280 |         27553 |        528434 |         40847 |
| tab_separated_20k.tsv                |   20000 |        248490 |         99572 |         30331 |        819672 |        127370 |       2127660 |        270270 |
| utf8_multibyte_20k.csv               |   20000 |        313480 |        159579 |         58741 |       1333333 |        189753 |       4000000 |        476190 |
| whitespace_heavy_20k.csv             |   20000 |        222933 |         98286 |         28152 |        680272 |        128617 |       1801802 |        239808 |
| wide_500_cols_20k.csv                |   20000 |          8302 |           620 |           347 |         14391 |          2859 |         56108 |          4308 |

---

## Speedup vs SmarterCSV 1.16.0 (C accelerated)

| File                                 |    Rows | CSV.read¹     | CSV.hashes¹   | CSV.table²    | SmarterCSV/C  | ZSV.read¹     | ZSV+wrapper²  |
|--------------------------------------|---------|---------------|---------------|---------------|---------------|---------------|---------------|
| PEOPLE_IMPORT_B.csv                  |   50000 |  2.86× slower |  7.96× slower | 24.17× slower |           ref |  2.74× faster |  2.68× slower |
| PEOPLE_IMPORT_C.csv                  |   50000 |  8.13× slower | 46.23× slower | 128.90× slower |          ref |  1.26× slower |  7.27× slower |
| PEOPLE_IMPORT_NB.csv                 |   50000 |  2.67× slower |  8.46× slower | 26.43× slower |           ref |  2.61× faster |  2.90× slower |
| PEOPLE_IMPORT_NC.csv                 |   50000 |  4.76× slower | 14.96× slower | 48.31× slower |           ref |  1.63× faster |  3.67× slower |
| uscities.csv                         |   31257 |  6.35× slower | 10.60× slower | 21.23× slower |           ref |  3.40× faster |  2.68× slower |
| uszips.csv                           |   33782 |  8.59× slower | 13.74× slower | 27.57× slower |           ref |  2.72× faster |  3.01× slower |
| worldcities.csv                      |   48059 |  6.25× slower |  9.88× slower | 20.11× slower |           ref |  3.68× faster |  2.20× slower |
| embedded_newlines_20k.csv            |   80000 |  2.77× slower |  4.01× slower |  7.17× slower |           ref | 12.11× faster |  1.46× faster |
| embedded_separators_20k.csv          |   20000 |  6.02× slower |  8.98× slower | 19.57× slower |           ref |  3.87× faster |  2.37× slower |
| heavy_quoting_20k.csv                |   20000 |  3.07× slower |  6.31× slower | 19.06× slower |           ref |  3.84× faster |  2.02× slower |
| long_fields_20k.csv                  |   20000 |  5.52× slower |  6.43× slower | 15.58× slower |           ref |  1.71× faster |  1.21× slower |
| many_empty_fields_20k.csv            |   20000 |  5.17× slower | 16.90× slower | 46.28× slower |           ref |  1.40× faster |  3.56× slower |
| multi_char_separator_20k.csv         |   20000 |  2.37× slower |  5.83× slower | 19.91× slower |           ref |           N/A |           N/A |
| sample_10M.csv                       |   50000 |  4.34× slower |  8.20× slower | 20.32× slower |           ref |  3.65× faster |  2.19× slower |
| sensor_data_50krows_50cols.csv       |   50000 |  2.18× slower | 10.21× slower | 24.04× slower |           ref |  2.73× faster |  4.73× slower |
| tab_separated_20k.tsv                |   20000 |  3.30× slower |  8.23× slower | 27.02× slower |           ref |  2.57× faster |  3.03× slower |
| utf8_multibyte_20k.csv               |   20000 |  4.25× slower |  8.35× slower | 22.70× slower |           ref |  3.33× faster |  2.80× slower |
| whitespace_heavy_20k.csv             |   20000 |  3.05× slower |  6.92× slower | 24.16× slower |           ref |  2.78× faster |  2.84× slower |
| wide_500_cols_20k.csv                |   20000 |  1.73× slower | 23.20× slower | 41.46× slower |           ref |  3.88× faster |  3.34× slower |

## Fair Comparison: equivalent-output adapters vs CSV.table

| File                                 |    Rows | CSV.table²    | SmarterCSV/C  | ZSV+wrapper²  |
|--------------------------------------|---------|---------------|---------------|---------------|
| PEOPLE_IMPORT_B.csv                  |   50000 |           ref | 24.17× faster |  9.01× faster |
| PEOPLE_IMPORT_C.csv                  |   50000 |           ref | 128.90× faster | 17.73× faster |
| PEOPLE_IMPORT_NB.csv                 |   50000 |           ref | 26.43× faster |  9.12× faster |
| PEOPLE_IMPORT_NC.csv                 |   50000 |           ref | 48.31× faster | 13.12× faster |
| uscities.csv                         |   31257 |           ref | 21.23× faster |  7.91× faster |
| uszips.csv                           |   33782 |           ref | 27.57× faster |  9.17× faster |
| worldcities.csv                      |   48059 |           ref | 20.11× faster |  9.08× faster |
| embedded_newlines_20k.csv            |   80000 |           ref |  7.17× faster |  9.56× faster |
| embedded_separators_20k.csv          |   20000 |           ref | 19.57× faster |  8.25× faster |
| heavy_quoting_20k.csv                |   20000 |           ref | 19.06× faster |  9.46× faster |
| long_fields_20k.csv                  |   20000 |           ref | 15.58× faster | 12.89× faster |
| many_empty_fields_20k.csv            |   20000 |           ref | 46.28× faster | 12.93× faster |
| multi_char_separator_20k.csv         |   20000 |           ref | 19.91× faster |           N/A |
| sample_10M.csv                       |   50000 |           ref | 20.32× faster |  9.29× faster |
| sensor_data_50krows_50cols.csv       |   50000 |           ref | 24.04× faster |  5.08× faster |
| tab_separated_20k.tsv                |   20000 |           ref | 27.02× faster |  8.86× faster |
| utf8_multibyte_20k.csv               |   20000 |           ref | 22.70× faster |  8.10× faster |
| whitespace_heavy_20k.csv             |   20000 |           ref | 24.16× faster |  8.52× faster |
| wide_500_cols_20k.csv                |   20000 |           ref | 41.46× faster | 12.37× faster |

## Head-to-Head: SmarterCSV 1.16.0 (C accelerated) vs ZSV+wrapper

| File                                 |    Rows | SmarterCSV/C  | ZSV+wrapper²  |
|--------------------------------------|---------|---------------|---------------|
| PEOPLE_IMPORT_B.csv                  |   50000 |           ref |  2.68× slower |
| PEOPLE_IMPORT_C.csv                  |   50000 |           ref |  7.27× slower |
| PEOPLE_IMPORT_NB.csv                 |   50000 |           ref |  2.90× slower |
| PEOPLE_IMPORT_NC.csv                 |   50000 |           ref |  3.67× slower |
| uscities.csv                         |   31257 |           ref |  2.68× slower |
| uszips.csv                           |   33782 |           ref |  3.01× slower |
| worldcities.csv                      |   48059 |           ref |  2.20× slower |
| embedded_newlines_20k.csv            |   80000 |           ref |  1.46× faster |
| embedded_separators_20k.csv          |   20000 |           ref |  2.37× slower |
| heavy_quoting_20k.csv                |   20000 |           ref |  2.02× slower |
| long_fields_20k.csv                  |   20000 |           ref |  1.21× slower |
| many_empty_fields_20k.csv            |   20000 |           ref |  3.56× slower |
| multi_char_separator_20k.csv         |   20000 |           N/A |           N/A |
| sample_10M.csv                       |   50000 |           ref |  2.19× slower |
| sensor_data_50krows_50cols.csv       |   50000 |           ref |  4.73× slower |
| tab_separated_20k.tsv                |   20000 |           ref |  3.03× slower |
| utf8_multibyte_20k.csv               |   20000 |           ref |  2.80× slower |
| whitespace_heavy_20k.csv             |   20000 |           ref |  2.84× slower |
| wide_500_cols_20k.csv                |   20000 |           ref |  3.34× slower |

## Raw Parsing: SmarterCSV 1.16.0 (C accelerated) vs ZSV.read

| File                                 |    Rows | SmarterCSV/C  | ZSV.read¹     |
|--------------------------------------|---------|---------------|---------------|
| PEOPLE_IMPORT_B.csv                  |   50000 |           ref |  2.74× faster |
| PEOPLE_IMPORT_C.csv                  |   50000 |           ref |  1.26× slower |
| PEOPLE_IMPORT_NB.csv                 |   50000 |           ref |  2.61× faster |
| PEOPLE_IMPORT_NC.csv                 |   50000 |           ref |  1.63× faster |
| uscities.csv                         |   31257 |           ref |  3.40× faster |
| uszips.csv                           |   33782 |           ref |  2.72× faster |
| worldcities.csv                      |   48059 |           ref |  3.68× faster |
| embedded_newlines_20k.csv            |   80000 |           ref | 12.11× faster |
| embedded_separators_20k.csv          |   20000 |           ref |  3.87× faster |
| heavy_quoting_20k.csv                |   20000 |           ref |  3.84× faster |
| long_fields_20k.csv                  |   20000 |           ref |  1.71× faster |
| many_empty_fields_20k.csv            |   20000 |           ref |  1.40× faster |
| multi_char_separator_20k.csv         |   20000 |           N/A |           N/A |
| sample_10M.csv                       |   50000 |           ref |  3.65× faster |
| sensor_data_50krows_50cols.csv       |   50000 |           ref |  2.73× faster |
| tab_separated_20k.tsv                |   20000 |           ref |  2.57× faster |
| utf8_multibyte_20k.csv               |   20000 |           ref |  3.33× faster |
| whitespace_heavy_20k.csv             |   20000 |           ref |  2.78× faster |
| wide_500_cols_20k.csv                |   20000 |           ref |  3.88× faster |

---

¹ **Raw output** — no post-processing applied. Returns plain arrays or string-keyed hashes.
  No header normalization, type conversion, whitespace stripping, or empty-value removal.
  Your own post-processing must be added to produce usable data.

² **Near-equivalent** to SmarterCSV output (symbol keys, numeric conversion), but not 100%
  identical. Whitespace handling, empty-value removal, and duplicate-header behavior may differ.
