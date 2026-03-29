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

# Lambda converters (issue #329: lambdas/Procs must be supported alongside class-based converters)
eu_date_lambda = ->(v) { v ? Date.strptime(v, '%m/%d/%Y') : nil }
currency_lambda = ->(v) { v ? v.sub(/[$]/, '').to_f : nil }
boolean_lambda = ->(v) {
  case v
  when /true/i then true
  when /false/i then false
  end
}

[true, false].each do |bool|
  describe ":value_converters with lambdas/Procs with#{bool ? ' C-' : 'out '}acceleration" do
    it 'converts date values using a lambda' do
      options = {acceleration: bool, value_converters: {date: eu_date_lambda}}
      data = SmarterCSV.process("#{fixture_path}/with_dates.csv", options)
      expect(data.flatten.size).to eq 3
      expect(data[0][:date].class).to eq Date
      expect(data[0][:date].to_s).to eq "1998-10-30"
      expect(data[1][:date].to_s).to eq "2011-02-01"
      expect(data[2][:date].to_s).to eq "2013-01-09"
    end

    it 'converts currency values using a lambda' do
      options = {acceleration: bool, value_converters: {price: currency_lambda}}
      data = SmarterCSV.process("#{fixture_path}/with_dates.csv", options)
      expect(data.flatten.size).to eq 3
      expect(data[0][:price].class).to eq Float
      expect(data[0][:price]).to eq 44.50
      expect(data[1][:price]).to eq 15.0
      expect(data[2][:price]).to eq 0.11
    end

    it 'converts boolean values using a lambda' do
      options = {acceleration: bool, value_converters: {member: boolean_lambda}}
      data = SmarterCSV.process("#{fixture_path}/with_dates.csv", options)
      expect(data.flatten.size).to eq 3
      expect(data[0][:member]).to eq true
      expect(data[1][:member]).to eq false
    end

    it 'supports mixing lambda and class-based converters' do
      options = {acceleration: bool, value_converters: {date: eu_date_lambda, price: CurrencyConverter}}
      data = SmarterCSV.process("#{fixture_path}/with_dates.csv", options)
      expect(data[0][:date].class).to eq Date
      expect(data[0][:date].to_s).to eq "1998-10-30"
      expect(data[0][:price]).to eq 44.50
    end
  end
end

[true, false].each do |bool|
  describe ":value_converters option with#{bool ? ' C-' : 'out '}acceleration" do
    it 'convert date values into Date instances' do
      options = {acceleration: bool, value_converters: {date: DateConverter}}
      data = SmarterCSV.process("#{fixture_path}/with_dates.csv", options)
      expect(data.flatten.size).to eq 3
      expect(data[0][:date].class).to eq Date
      expect(data[0][:date].to_s).to eq "1998-10-30"
      expect(data[1][:date].to_s).to eq "2011-02-01"
      expect(data[2][:date].to_s).to eq "2013-01-09"
    end

    it 'converts dollar prices into float values' do
      options = {acceleration: bool, value_converters: {price: CurrencyConverter}}
      data = SmarterCSV.process("#{fixture_path}/money.csv", options)
      expect(data.flatten.size).to eq 2
      expect(data[0][:price].class).to eq Float
      expect(data[0][:price]).to eq 9.99
      expect(data[1][:price]).to eq 14.99
    end

    it 'convert can use multiple value converters' do
      options = {acceleration: bool, value_converters: {date: DateConverter, price: CurrencyConverter}}
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

    it 'converts boolean values into true/false' do
      options = {acceleration: bool, value_converters: {member: BooleanConverter}}
      data = SmarterCSV.process("#{fixture_path}/with_dates.csv", options)
      expect(data.flatten.size).to eq 3
      expect(data[0][:member]).to eq true
      expect(data[1][:member]).to eq false
    end
  end
end
