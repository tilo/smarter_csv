
### Contents

  * [Introduction](./_introduction.md)
  * [The Basic Read API](./basic_read_api.md)
  * [The Basic Write API](./basic_write_api.md)
  * [Batch Processing](././batch_processing.md)
  * [**Configuration Options**](./options.md)
  * [Row and Column Separators](./row_col_sep.md)
  * [Header Transformations](./header_transformations.md)
  * [Header Validations](./header_validations.md)
  * [Data Transformations](./data_transformations.md)
  * [Value Converters](./value_converters.md)
    
--------------   

# Configuration Options

## CSV Writing

     | Option                      | Default  |  Explanation                                                                         |
     ---------------------------------------------------------------------------------------------------------------------------------
     | :row_sep                    |   $/      | Separates rows; Defaults to your OS row separator. `/n` on UNIX, `/r/n` oon Windows | 
     | :col_sep                    |   ","     | Separates each value in a row                                  | 
     | :quote_char                 |   '"'     | To quote CSV fields.                                           |
     | :force_quotes               |   false   | Forces each individual value to be quoted |
     | :headers                    |    []     | You can provide the specific list of keys from the input you'd like to be used as headers in the CSV file |
     |                             |           | ⚠️ This disables automatic header detection!                    |
     | :map_headers                |    {}     | Similar to `headers`, but also maps each desired key to a user-specified value that is uesd as the header. | 
     |                             |           | ⚠️ This disables automatic header detection!                    |
     | :value_converters           |    nil    | allows to define lambdas to programmatically modify values       |
     |                             |           | * either for specific `key` names                                |
     |                             |           | * or using `_all` for all fields                                |
     | :header_converter           |    nil    | allows to define one lambda to programmatically modify the headers |
     | :discover_headers           |   true    | Automatically detects all keys in the input before writing the header |
     |                             |           | Do not manually set this to `false`. ⚠️                         |
     |                             |           | But you can set this to `true` when using `map_headers` option. |
     | :disable_auto_quoting       |  false    | To manually disable auto-quoting of special characters. ⚠️ Be careful with this! |
     | :quote_headers              |  false    | To force quoting all headers (only needed in rare cases)        |


## CSV Reading

     | Option                      | Default  |  Explanation                                                                         |
     ---------------------------------------------------------------------------------------------------------------------------------
     | :chunk_size                 |   nil    | if set, determines the desired chunk-size (defaults to nil, no chunk processing)     |
     |                             |          |                                                                                      |
     | :file_encoding              |   utf-8  | Set the file encoding eg.: 'windows-1252' or 'iso-8859-1'                            |
     | :invalid_byte_sequence      |   ''     | what to replace invalid byte sequences with                                          |
     | :force_utf8                 |   false  | force UTF-8 encoding of all lines (including headers) in the CSV file                |
     | :skip_lines                 |   nil    | how many lines to skip before the first line or header line is processed             |
     | :comment_regexp             |   nil    | regular expression to ignore comment lines (see NOTE on CSV header), e.g./\A#/       |
     ---------------------------------------------------------------------------------------------------------------------------------
     | :col_sep                    |  :auto   | column separator (default was ',')                                                   |
     | :row_sep                    |  :auto   | row separator or record separator (previous default was system's $/ , which defaulted to "\n") |
     |                             |          | This can also be set to :auto, but will process the whole cvs file first  (slow!)    |
     | :auto_row_sep_chars         |   500    | How many characters to analyze when using `:row_sep => :auto`. nil or 0 means whole file. |
     | :quote_char                 |   '"'    | quotation character                                                                  |
     ---------------------------------------------------------------------------------------------------------------------------------
     | :headers_in_file            |  true(1) | Whether or not the file contains headers as the first line.                          |
     |                             |          | (1): if `user_provided_headers` is given, the default is `false`,                    |
     |                             |          | unless you specify it to be explicitly `true`.                                       |
     |                             |          | This prevents losing the first line of data, which is otherwise assumed to be a header. |
     | :duplicate_header_suffix    |   ''     | Adds numbers to duplicated headers and separates them by the given suffix.           |
     |                             |          | Set this to nil to raise `DuplicateHeaders` error instead (previous behavior)        |
     | :user_provided_headers      |   nil    | *careful with that axe!*                                                             |
     |                             |          | user provided Array of header strings or symbols, to define                          |
     |                             |          | what headers should be used, overriding any in-file headers.                         |
     |                             |          | You can not combine the :user_provided_headers and :key_mapping options              |
     | :remove_empty_hashes        |   true   | remove / ignore any hashes which don't have any key/value pairs or all empty values  |
     | :verbose                    |   false  | print out line number while processing (to track down problems in input files)       |
     | :with_line_numbers          |   false  | add :csv_line_number to each data hash                                               |
     | :missing_header_prefix      |  column_ | can be set to a string of your liking                                                |
     | :strict                     |   false  | When set to `true`, extra columns will raise MalformedCSV exception                  |
     ---------------------------------------------------------------------------------------------------------------------------------

Additional 1.x Options which may be replaced in 2.0

There have been a lot of 1-offs and feature creep around these options, and going forward we'll strive to have a simpler, but more flexible way to address these features.


     | Option                      | Default  |  Explanation                                                                         |
     ---------------------------------------------------------------------------------------------------------------------------------
     | :key_mapping                |   nil    | a hash which maps headers from the CSV file to keys in the result hash               |
     | :silence_missing_keys        |   false  | ignore missing keys in `key_mapping`                                                |
     |                             |          | if set to true: makes all mapped keys optional                                       |
     |                             |          | if given an array, makes only the keys listed in it optional                         |
     | :required_keys              |   nil    | An array. Specify the required names AFTER header transformation.                    |
     | :required_headers           |   nil    | (DEPRECATED / renamed) Use `required_keys` instead                                   |
     |                             |          | or an exception is raised   No validation if nil is given.                           |
     | :remove_unmapped_keys       |   false  | when using :key_mapping option, should non-mapped keys / columns be removed?         |
     | :downcase_header            |   true   | downcase all column headers                                                          |
     | :strings_as_keys            |   false  | use strings instead of symbols as the keys in the result hashes                      |
     | :strip_whitespace           |   true   | remove whitespace before/after values and headers                                    |
     | :keep_original_headers      |   false  | keep the original headers from the CSV-file as-is.                                   |
     |                             |          | Disables other flags manipulating the header fields.                                 |
     | :strip_chars_from_headers   |   nil    | RegExp to remove extraneous characters from the header line (e.g. if headers are quoted) |
     ---------------------------------------------------------------------------------------------------------------------------------
     | :value_converters           |   nil    | supply a hash of :header => KlassName; the class needs to implement self.convert(val)|
     | :remove_empty_values        |   true   | remove values which have nil or empty strings as values                              |
     | :remove_zero_values         |   false  | remove values which have a numeric value equal to zero / 0                           |
     | :remove_values_matching     |   nil    | removes key/value pairs if value matches given regular expressions. e.g.:            |
     |                             |          | /^\$0\.0+$/ to match $0.00 , or /^#VALUE!$/ to match errors in Excel spreadsheets    |
     | :convert_values_to_numeric  |   true   | converts strings containing Integers or Floats to the appropriate class              |
     |                             |          |      also accepts either {:except => [:key1,:key2]} or {:only => :key3}              |
     ---------------------------------------------------------------------------------------------------------------------------------

-------------
PREVIOUS: [Batch Processing](./batch_processing.md) | NEXT: [Row and Column Separators](./row_col_sep.md)
