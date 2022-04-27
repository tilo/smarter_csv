
# SmarterCSV 1.x Change Log

## 1.5.1 (2022-04-27)
  * added raising of `KeyMappingError` if `key_mapping` refers to a non-existent key
  * added option `duplicate_header_suffix` (thanks to Skye Shaw)
    When given a non-nil string, it uses the suffix to append numbering 2..n to duplicate headers.
    If your code will need to process arbitrary CSV files, please set `duplicate_header_suffix`.

## 1.5.0 (2022-04-25)
  * fixed bug with trailing col_sep characters, introduced in 1.4.0
  * Fix deprecation warning in Ruby 3.0.3 / $INPUT_RECORD_SEPARATOR (thanks to Joel Fouse )

  * changed default for `comment_regexp` to be `nil` for a safer default behavior (thanks to David Lazar)
  **Note**
    This no longer assumes that lines starting with `#` are comments.
    If you want to treat lines starting with '#' as comments, use `comment_regexp: /\A#/`

## 1.4.2 (2022-02-12)
  * fixed issue with simplecov

## 1.4.1 (2022-02-12) (PULLED)
  * minor fix: also support `col_sep: :auto`
  * added simplecov

## 1.4.0 (2022-02-11)
  * dropped GPL license, smarter_csv is now only using the MIT License
  * added experimental option `col_sep: 'auto` to auto-detect the column separator (issue #183)
    The default behavior is still to assume `,` is the column separator. 
  * fixed buggy behavior when using `remove_empty_values: false` (issue #168)
  * fixed Ruby 3.0 deprecation

## 1.3.0 (2022-02-06) Breaking code change if you used `--key_mappings`
 * fix bug for key_mappings (issue #181)   
   The values of the `key_mappings` hash will now be used "as is", and no longer forced to be symbols

   **Users with existing code with `--key_mappings` need to change their code** to 
     * either use symbols in the `key_mapping` hash
     * or change the expected keys from symbols to strings

## 1.2.9 (2021-11-22) (PULLED)
 * fix bug for key_mappings (issue #181)
   The values of the `key_mappings` hash will now be used "as is", and no longer forced to be symbols

## 1.2.8 (2020-02-04)
 * fix deprecation warnings on Ruby 2.7 (thank to Diego Salido)

## 1.2.7 (2020-02-03)

## 1.2.6 (2018-11-13)
 * fixing error caused by calling f.close when we do not hand in a file

## 1.2.5 (2018-09-16)
 * fixing issue #136 with comments in CSV files
 * fixing error class hierarchy

## 1.2.4 (2018-08-06)
 * using Rails blank? if it's available

## 1.2.3 (2018-01-27)
 * fixed regression / test
 * fuxed quote_char interpolation for headers, but not data (thanks to Colin Petruno)
 * bugfix (thanks to Joshua Smith for reporting)

## 1.2.0 (2018-01-20)
 * add default validation that a header can only appear once
 * add option `required_headers`

## 1.1.5 (2017-11-05)
 * fix issue with invalid byte sequences in header (issue #103, thanks to Dave Myron)
 * fix issue with invalid byte sequences in multi-line data (thanks to Ivan Ushakov)
 * analyze only 500 characters by default when `:row_sep => :auto` is used.
   added option `row_sep_auto_chars` to change the default if necessary. (thanks to Matthieu Paret)

## 1.1.4 (2017-01-16)
 * fixing UTF-8 related bug which was introduced in 1.1.2 (thanks to Tirdad C.)

## 1.1.3 (2016-12-30)
 * added warning when options indicate UTF-8 processing, but input filehandle is not opened with r:UTF-8 option

## 1.1.2 (2016-12-29)
 * added option `invalid_byte_sequence` (thanks to polycarpou)
 * added comments on handling of UTF-8 encoding when opening from File vs. OpenURI (thanks to KevinColemanInc)

## 1.1.1 (2016-11-26)
 * added option to `skip_lines` (thanks to wal)
 * added option to `force_utf8` encoding (thanks to jordangraft)
 * bugfix if no headers in input data (thanks to esBeee)
 * ensure input file is closed (thanks to waldyr)
 * improved verbose output (thankd to benmaher)
 * improved documentation

## 1.1.0 (2015-07-26)
 * added feature :value_converters, which allows parsing of dates, money, and other things (thanks to Raphaël Bleuse, Lucas Camargo de Almeida, Alejandro)
 * added error if :headers_in_file is set to false, and no :user_provided_headers are given (thanks to innhyu)
 * added support to convert dashes to underscore characters in headers (thanks to César Camacho)
 * fixing automatic detection of \r\n line-endings (thanks to feens)

## 1.0.19 (2014-10-29)
 * added option :keep_original_headers to keep CSV-headers as-is (thanks to Benjamin Thouret)

## 1.0.18 (2014-10-27)
 * added support for multi-line fields / csv fields containing CR (thanks to Chris Hilton) (issue #31)

## 1.0.17 (2014-01-13)
 * added option to set :row_sep to :auto , for automatic detection of the row-separator (issue #22)

## 1.0.16 (2014-01-13)
 * :convert_values_to_numeric option can now be qualified with :except or :only (thanks to Hugo Lepetit)
 * removed deprecated `process_csv` method

## 1.0.15 (2013-12-07)
 * new option:
   * :remove_unmapped_keys  to completely ignore columns which were not mapped with :key_mapping (thanks to Dave Sanders)

## 1.0.14 (2013-11-01)
 * added GPL-2 and MIT license to GEM spec file; if you need another license contact me

## 1.0.12 (2013-10-15)
 * added RSpec tests

## 1.0.11 (2013-09-28)
 * bugfix : fixed issue #18 - fixing issue with last chunk not being properly returned (thanks to Jordan Running)
 * added RSpec tests

## 1.0.10 (2013-06-26)
 * bugfix : fixed issue #14 - passing options along to CSV.parse (thanks to Marcos Zimmermann)

## 1.0.9 (2013-06-19)
 * bugfix : fixed issue #13 with negative integers and floats not being correctly converted (thanks to Graham Wetzler)

## 1.0.8 (2013-06-01)

 * bugfix : fixed issue with nil values in inputs with quote-char (thanks to Félix Bellanger)
 * new options:
    * :force_simple_split : to force simiple splitting on :col_sep character for non-standard CSV-files. e.g. without properly escaped :quote_char
    * :verbose : print out line number while processing (to track down problems in input files)

## 1.0.7 (2013-05-20)

 * allowing process to work with objects with a 'readline' method (thanks to taq)
 * added options:
    * :file_encoding : defaults to utf8  (thanks to MrTin, Paxa)

## 1.0.6 (2013-05-19)

 * bugfix : quoted fields are now correctly parsed

## 1.0.5 (2013-05-08)

 * bugfix : for :headers_in_file option

## 1.0.4 (2012-08-17)

 * renamed the following options:
    * :strip_whitepace_from_values => :strip_whitespace   - removes leading/trailing whitespace from headers and values

## 1.0.3 (2012-08-16)

 * added the following options:
    * :strip_whitepace_from_values   - removes leading/trailing whitespace from values

## 1.0.2 (2012-08-02)

 * added more options for dealing with headers:
    * :user_provided_headers ,user provided Array with header strings or symbols, to precisely define what the headers should be, overriding any in-file headers (default: nil)
    * :headers_in_file , if the file contains headers as the first line (default: true)

## 1.0.1 (2012-07-30)

 * added the following options:
    * :downcase_header
    * :strings_as_keys
    * :remove_zero_values
    * :remove_values_matching
    * :remove_empty_hashes
    * :convert_values_to_numeric

 * renamed the following options:
    * :remove_empty_fields => :remove_empty_values


## 1.0.0 (2012-07-29)

 * renamed `SmarterCSV.process_csv` to `SmarterCSV.process`.

## 1.0.0.pre1 (2012-07-29)
