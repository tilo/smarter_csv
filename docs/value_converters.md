
### Contents

  * [Introduction](./_introduction.md)
  * [Migrating from Ruby CSV](./migrating_from_csv.md)
  * [Parsing Strategy](./parsing_strategy.md)
  * [The Basic Read API](./basic_read_api.md)
  * [The Basic Write API](./basic_write_api.md)
  * [Batch Processing](././batch_processing.md)
  * [Configuration Options](./options.md)
  * [Row and Column Separators](./row_col_sep.md)
  * [Header Transformations](./header_transformations.md)
  * [Header Validations](./header_validations.md)
  * [Column Selection](./column_selection.md)
  * [Data Transformations](./data_transformations.md)
  * [**Value Converters**](./value_converters.md)
  * [Bad Row Quarantine](./bad_row_quarantine.md)
  * [Examples](./examples.md)
  * [SmarterCSV over the Years](./history.md)

--------------

# Using Value Converters for Reading CSV

Value Converters allow you to do custom transformations specific rows, to help you massage the data so it fits the expectations of your down-stream process, such as creating a DB record.

If you use `key_mappings` and `value_converters`, make sure that the value converters references the keys based on the final mapped name, not the original name in the CSV file.

```ruby
    $ cat spec/fixtures/with_dates.csv
    first,last,date,price,member
    Ben,Miller,10/30/1998,$44.50,TRUE
    Tom,Turner,2/1/2011,$15.99,False
    Ken,Smith,01/09/2013,$199.99,true

    $ irb
    > require 'smarter_csv'
    > require 'date'

    # define a custom converter class, which implements self.convert(value)
    class DateConverter
      def self.convert(value)
        Date.strptime( value, '%m/%d/%Y') # parses custom date format into Date instance
      end
    end

    class DollarConverter
      def self.convert(value)
        value.sub('$','').to_f # strips the dollar sign and creates a Float value
      end
    end

    require 'money'
    class MoneyConverter
      def self.convert(value)
        # depending on locale you might want to also remove the indicator for thousands, e.g. comma 
        Money.from_amount(value.gsub(/[\s\$]/,'').to_f) # creates a Money instance (based on cents)
      end
    end

    class BooleanConverter
      def self.convert(value)
        case value
        when /true/i
          true
        when /false/i
          false
        else
          nil
        end
      end
    end

    options = {value_converters: {date: DateConverter, price: DollarConverter, member: BooleanConverter}}
    data = SmarterCSV.process("spec/fixtures/with_dates.csv", options)
    first_record = data.first
    first_record[:date]
      => #<Date: 1998-10-30 ((2451117j,0s,0n),+0s,2299161j)>
    first_record[:date].class
      => Date
    first_record[:price]
      => 44.50
    first_record[:price].class
      => Float
    first_record[:member]
      => true
```

## Why there are no built-in Date / Time / DateTime converters

SmarterCSV intentionally does not ship built-in date or time converters. The reason is
**localization (L10N)**: date formats vary widely across regions and there is no single
correct interpretation of a bare string like `"12/03/2020"` — it is December 3rd in the
United States but March 12th in most of Europe.

Ruby's standard library `Date.parse` / `DateTime.parse` handle ISO 8601 and a handful of
English-language formats, but they are not locale-aware and will silently produce the wrong
date for locale-specific formats. Shipping a built-in converter that is wrong for half the
world's locales would be worse than shipping none.

The right solution is a `value_converter` with an explicit format string tuned to your data:

```ruby
require 'date'

# US format: MM/DD/YYYY
us_date = ->(v) { Date.strptime(v, '%m/%d/%Y') rescue v }

# European format: DD.MM.YYYY
eu_date = ->(v) { Date.strptime(v, '%d.%m.%Y') rescue v }

# ISO 8601 (unambiguous, safe to use without rescue)
iso_date = ->(v) { Date.iso8601(v) rescue v }

options = {
  value_converters: {
    birth_date:  eu_date,
    created_at:  iso_date,
    invoiced_on: us_date,
  }
}
data = SmarterCSV.process('records.csv', options)
```

For locale-aware parsing of user-supplied date strings (e.g., "3. Oktober 2024" in German),
consider the [`delocalize`](https://github.com/clemens/delocalize) gem, which integrates
with Rails' I18n locale configuration. For natural-language date strings, consider
[`chronic`](https://github.com/mojombo/chronic).

--------------------
PREVIOUS: [Data Transformations](./data_transformations.md) | NEXT: [Bad Row Quarantine](./bad_row_quarantine.md) | UP: [README](../README.md)
