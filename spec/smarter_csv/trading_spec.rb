# frozen_string_literal: true

require 'spec_helper'

fixture_path = 'spec/fixtures'

# somebody reported that a column called 'options_trader' would be truncated to 'trader'

describe 'loads simple file format' do
  it 'with symbols as keys when using v1 defaults' do
    options = {defaults: 'v1'}
    data = SmarterCSV.process("#{fixture_path}/trading.csv", options)

    data.flatten.size.should eq 2
    data.each do |item|
      # all keys should be symbols when using v1.x backwards compatible mode
      item.each_key{|x| x.class.should eq Symbol}

      # Ruby 2.4+ unifies Fixnum & Bignum into Integer.
      item[:account_id].class.should eq Integer
      item[:shares_issued].class.should eq Integer
      item[:options_trader].class.should eq String
      item[:stock_symbol].class.should eq String
      item[:purchase_date].class.should eq String
    end
  end

  it 'with symbols as keys when using defaults' do
    options = {}
    data = SmarterCSV.process("#{fixture_path}/trading.csv", options)

    data.flatten.size.should eq 2
    data.each do |item|
      # all keys should be symbols when using v1.x backwards compatible mode
      item.each_key{|x| x.class.should eq Symbol}
      item[:account_id].class.should eq String
      item[:options_trader].class.should eq String
      item[:stock_symbol].class.should eq String
      item[:shares_issued].class.should eq String
      item[:purchase_date].class.should eq String
    end
  end

  it 'with symbols as keys when using defaults' do
    options = {
      header_transformations: [:none, :keys_as_strings]
    }
    data = SmarterCSV.process("#{fixture_path}/trading.csv", options)

    data.flatten.size.should eq 2
    data.each do |item|
      # all keys should be symbols when using v1.x backwards compatible mode
      item.each_key{|x| x.class.should eq String}
      item['account_id'].class.should eq String
      item['options_trader'].class.should eq String
      item['stock_symbol'].class.should eq String
      item['shares_issued'].class.should eq String
      item['purchase_date'].class.should eq String
    end
  end
end
