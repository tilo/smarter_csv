require 'spec_helper'

fixture_path = 'spec/fixtures'

require 'date'
class DateConverter
  def self.convert(value)
    Date.strptime( value, '%m/%d/%Y')
  end
end

class CurrencyConverter
  def self.convert(value)
    value.sub(/[$]/,'').to_f  # would be nice to add a computed column :currency => '€'
  end
end

describe 'be_able_to' do
  it 'convert date values into Date instances' do
    options = {:value_converters => {:date => DateConverter}}
    data = SmarterCSV.process("#{fixture_path}/with_dates.csv", options)
    data.flatten.size.should == 3
    data[0][:date].class.should eq Date
    data[0][:date].to_s.should eq "1998-10-30"
    data[1][:date].to_s.should eq "2011-02-01"
    data[2][:date].to_s.should eq "2013-01-09"
  end

  it 'converts dollar prices into float values' do
    options = {:value_converters => {:price => CurrencyConverter}}
    data = SmarterCSV.process("#{fixture_path}/money.csv", options)
    data.flatten.size.should == 2
    data[0][:price].class.should eq Float
    data[0][:price].should eq 9.99
    data[1][:price].should eq 14.99
  end

  it 'convert can use multiple value converters' do
    options = {:value_converters => {:date => DateConverter, :price => CurrencyConverter}}
    data = SmarterCSV.process("#{fixture_path}/with_dates.csv", options)
    data.flatten.size.should == 3
    data[0][:date].class.should eq Date
    data[0][:date].to_s.should eq "1998-10-30"
    data[1][:date].to_s.should eq "2011-02-01"
    data[2][:date].to_s.should eq "2013-01-09"

    data[0][:price].class.should eq Float
    data[0][:price].should eq 44.50
    data[1][:price].should eq 15.0
    data[2][:price].should eq 0.11
  end
end
