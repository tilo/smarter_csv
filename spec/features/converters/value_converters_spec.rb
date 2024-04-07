# frozen_string_literal: true

fixture_path = 'spec/fixtures'

require 'date'
class DateConverter
  def self.convert(value)
    Date.strptime(value, '%m/%d/%Y')
  end
end

class CurrencyConverter
  def self.convert(value)
    value.sub(/[$]/, '').to_f # would be nice to add a computed column :currency => '€'
  end
end

describe ':value_converters option' do
  it 'convert date values into Date instances' do
    options = {value_converters: {date: DateConverter}}
    data = SmarterCSV.process("#{fixture_path}/with_dates.csv", options)
    expect(data.flatten.size).to eq 3
    expect(data[0][:date].class).to eq Date
    expect(data[0][:date].to_s).to eq "1998-10-30"
    expect(data[1][:date].to_s).to eq "2011-02-01"
    expect(data[2][:date].to_s).to eq "2013-01-09"
  end

  it 'converts dollar prices into float values' do
    options = {value_converters: {price: CurrencyConverter}}
    data = SmarterCSV.process("#{fixture_path}/money.csv", options)
    expect(data.flatten.size).to eq 2
    expect(data[0][:price].class).to eq Float
    expect(data[0][:price]).to eq 9.99
    expect(data[1][:price]).to eq 14.99
  end

  it 'convert can use multiple value converters' do
    options = {value_converters: {date: DateConverter, price: CurrencyConverter}}
    data = SmarterCSV.process("#{fixture_path}/with_dates.csv", options)
    expect(data.flatten.size).to eq 3
    expect(data[0][:date].class).to eq Date
    expect(data[0][:date].to_s).to eq "1998-10-30"
    expect(data[1][:date].to_s).to eq "2011-02-01"
    expect(data[2][:date].to_s).to eq "2013-01-09"

    expect(data[0][:price].class).to eq Float
    expect(data[0][:price]).to eq 44.50
    expect(data[1][:price]).to eq 15.0
    expect(data[2][:price]).to eq 0.11
  end
end
