
### Contents

  * [Introduction](./_introduction.md)
  * [The Basic API](./basic_api.md)
  * [Batch Processing](././batch_processing.md)
  * [Configuration Options](./options.md)
  * [Row and Column Separators](./row_col_sep.md)
  * [Header Transformations](./header_transformations.md)
  * [Header Validations](./header_validations.md)
  * [Data Transformations](./data_transformations.md)
  * [**Value Converters**](./value_converters.md)
    
--------------  

# Using Value Converters

Value Converters allow you to do custom transformations specific rows, to help you massage the data so it fits the expectations of your down-stream process, such as creating a DB record.

If you use `key_mappings` and `value_converters`, make sure that the value converters references the keys based on the final mapped name, not the original name in the CSV file.

```ruby
    $ cat spec/fixtures/with_dates.csv
    first,last,date,price
    Ben,Miller,10/30/1998,$44.50
    Tom,Turner,2/1/2011,$15.99
    Ken,Smith,01/09/2013,$199.99

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

    options = {:value_converters => {:date => DateConverter, :price => DollarConverter}}
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
```

--------------------
PREVIOUS: [Data Transformations](./data_transformations.md) | UP: [README](../README.md)
