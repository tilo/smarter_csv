
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
  * [Instrumentation Hooks](./instrumentation.md)
  * [Examples](./examples.md)
  * [Real-World CSV Files](./real_world_csv.md)
  * [SmarterCSV over the Years](./history.md)
  * [Release Notes](./releases/1.16.0/changes.md)

--------------

# Using Value Converters for Reading CSV

Value converters let you transform raw CSV strings into the types your downstream code
expects — dates, booleans, numbers, Money objects, whatever you need. They run per-key,
after SmarterCSV has parsed and mapped the headers.

A converter is either a **lambda** (for simple inline cases) or a **class** implementing
`self.convert(value)` (for reusable, independently testable converters). Both forms are
fully supported.

The examples throughout this page use the following fixture file:

```
first,last,date,price,member
Ben,Miller,10/30/1998,$44.50,TRUE
Tom,Turner,2/1/2011,$15.99,False
Ken,Smith,01/09/2013,$199.99,true
```

> **Key mapping interaction:** if you use `key_mapping:`, converters must reference the
> **mapped** key name, not the original CSV header name. The mapping runs first; converters
> see the final key.

## Lambda Converters

Lambdas are the quickest way to define a converter inline.

**Boolean:**

```ruby
bool = ->(v) { v&.match?(/\Atrue\z/i) }

data = SmarterCSV.process('records.csv', value_converters: { active: bool, verified: bool })
# "TRUE"  => true
# "false" => false
# nil     => nil  (& guard handles missing/empty fields)
```

**Strip currency symbol and convert to Float:**

```ruby
dollar = ->(v) { v&.sub('$', '')&.to_f }

data = SmarterCSV.process('records.csv', value_converters: { price: dollar, tax: dollar })
# "$44.50" => 44.5
# nil      => nil
```

**Reusing the same lambda across multiple keys:**

```ruby
date = ->(v) { v ? Date.strptime(v, '%m/%d/%Y') : nil }

data = SmarterCSV.process('records.csv', value_converters: { start_date: date, end_date: date })
```

**`key_mapping` + `value_converters` — always use the mapped name:**

```ruby
# CSV header is "MemberSince" — mapped to :member_since
options = {
  key_mapping:      { membersince: :member_since },
  value_converters: { member_since: ->(v) { v ? Date.strptime(v, '%m/%d/%Y') : nil } },
}
data = SmarterCSV.process('records.csv', options)
```

## Handling nil and Empty Fields

Converters receive the raw string value from the CSV field. If a field is blank or missing,
the value passed to your converter may be `nil` or `""`. Always guard against this:

```ruby
# Safe: returns nil for blank fields instead of raising
price = ->(v) { v&.sub('$', '')&.to_f }

# Unsafe: raises NoMethodError when v is nil
price = ->(v) { v.sub('$', '').to_f }
```

For class-based converters, add an explicit guard at the top of `self.convert`:

```ruby
def self.convert(value)
  return nil if value.nil? || value.empty?
  # ... rest of conversion
end
```

## Class-Based Converters

For converters you want to reuse across the codebase or test independently, define a class
with a `self.convert(value)` class method:

```ruby
require 'date'

class DateConverter
  def self.convert(value)
    return nil if value.nil? || value.empty?
    Date.strptime(value, '%m/%d/%Y')
  end
end

class DollarConverter
  def self.convert(value)
    return nil if value.nil? || value.empty?
    value.sub('$', '').to_f
  end
end

class BooleanConverter
  def self.convert(value)
    case value
    when /\Atrue\z/i  then true
    when /\Afalse\z/i then false
    end
  end
end

options = {
  value_converters: {
    date:   DateConverter,
    price:  DollarConverter,
    member: BooleanConverter,
  }
}
data = SmarterCSV.process('spec/fixtures/with_dates.csv', options)

data.first[:date]   #=> #<Date: 1998-10-30>
data.first[:price]  #=> 44.5
data.first[:member] #=> true
```

## Money Converter

For applications using the [`money`](https://github.com/RubyMoney/money) gem:

```ruby
require 'money'

class MoneyConverter
  def self.convert(value)
    return nil if value.nil? || value.empty?
    # remove currency symbol and thousands separators before converting
    Money.from_amount(value.gsub(/[\s$,]/, '').to_f)
  end
end

data = SmarterCSV.process('invoices.csv', value_converters: { amount: MoneyConverter })
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
