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
