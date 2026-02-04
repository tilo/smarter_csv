require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'load basic CSV file' do

  let!(:filename) { "#{fixture_path}/floats_and_dates.csv" }

  describe 'default behavior' do

    # SmarterCSV default is converting values to numeric and using symbols as keys
    #
    it 'should convert floats and use symbol keys with defaults' do
      data = SmarterCSV.process(filename, {})
      expect(data.size).to eq 11

      # all the keys should be symbols (default)
      data.each do |item|
        item.keys.each do |x|
          expect(x.class).to eq Symbol
        end
      end

      # First row has valid float format (1399999.99), should be converted
      expect(data[0][:price].class).to eq Float
      expect(data[0][:price]).to eq 1399999.99

      # Other rows have special formats (currency symbols, commas) - should stay as strings
      data[1..].each do |h|
        expect(h[:price].class).to eq String
      end
    end

    it 'should NOT convert floats when convert_values_to_numeric is false' do
      data = SmarterCSV.process(filename, { convert_values_to_numeric: false })
      expect(data.size).to eq 11

      # all the keys should be symbols (default)
      data.each { |item| item.keys.each { |x| expect(x.class).to eq Symbol } }

      # All prices should remain as strings
      data.each do |h|
        expect(h[:price].class).to eq String
      end
    end

    it 'should use string keys when strings_as_keys is true' do
      options = { strings_as_keys: true }
      data = SmarterCSV.process(filename, options)
      expect(data.size).to eq 11

      # all the keys should be strings
      data.each { |item| item.keys.each { |x| expect(x.class).to eq String } }

      data.each do |h|
        expect(['date', 'part_no', 'quantity', 'product_name', 'price']).to include(*h.keys)
      end
    end

    it 'should preserve original header case when downcase_header is false' do
      options = { strings_as_keys: true, downcase_header: false }
      data = SmarterCSV.process(filename, options)
      expect(data.size).to eq 11

      # all the keys should be strings with original case
      data.each { |item| item.keys.each { |x| expect(x.class).to eq String } }

      data.each do |h|
        expect(['Date', 'Part_No', 'Quantity', 'Product_Name', 'Price']).to include(*h.keys)
      end
    end
  end

  describe 'parsing floats' do

    it 'should convert floats by default' do
      data = SmarterCSV.process(filename, {})
      expect(data.size).to eq 11

      # all the keys should be symbols
      data.each { |item| item.keys.each { |x| expect(x.class).to eq Symbol } }

      # First row price is a valid float
      expect(data[0][:price]).to eq 1399999.99
      expect(data[0][:price].class).to eq Float
    end

    it 'should not convert floats when convert_values_to_numeric is false' do
      options = { convert_values_to_numeric: false }
      data = SmarterCSV.process(filename, options)
      expect(data.size).to eq 11

      data.each do |h|
        expect(h[:price].class).to eq String
      end
    end
  end
end
