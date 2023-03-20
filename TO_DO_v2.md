# SmarterCSV v2.0 TO DO List

* add enumerable to speed up parallel processing [issue #66](https://github.com/tilo/smarter_csv/issues/66), [issue #32](https://github.com/tilo/smarter_csv/issues/32)
* use Procs for validations and transformatoins [issue #118](https://github.com/tilo/smarter_csv/issues/118)
* make @errors and @warnings work [issue #118](https://github.com/tilo/smarter_csv/issues/118)
* skip file opening, allow reading from CSV string, e.g. reading from S3 file [issue #120](https://github.com/tilo/smarter_csv/issues/120).
  Or stream large file from S3 (linked in the issue)
* Collect all Errors, before surfacing them. Avoid throwing an exception on the first error [issue #133](https://github.com/tilo/smarter_csv/issues/133)
* Don't call rewind on filehandle
* [2.0 BUG] :convert_values_to_numeric_unless_leading_zeros drops leading zeros [issue #151](https://github.com/tilo/smarter_csv/issues/151)
* [2.0 BUG]  convert_to_float saves Proc as @@convert_to_integer [issue #157](https://github.com/tilo/smarter_csv/issues/157)
* Provide an example for custom Procs for hash_transformations in the docs [issue #174](https://github.com/tilo/smarter_csv/issues/174)
* Replace remove_empty_values: false [issue #213](https://github.com/tilo/smarter_csv/issues/213)

