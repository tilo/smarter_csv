# frozen_string_literal: true

require 'spec_helper'

fixture_path = 'spec/fixtures'

# somebody reported that a column called 'options_trader' would be truncated to 'trader'

describe 'loads simple file format' do
  it 'with symbols as keys when using defaults' do
    options = {}
    data = SmarterCSV.process("#{fixture_path}/trading.csv", options)
    expect(data.flatten.size).to eq 2

    data.each do |hash|
      # all keys should be symbols when using v1.x backwards compatible mode
      hash.each_key do |key|
        expect(key.class).to eq Symbol
      end

      expect(hash[:account_id].class).to eq Fixnum
      expect(hash[:options_trader].class).to eq String
      expect(hash[:stock_symbol].class).to eq String
      expect(hash[:shares_issued].class).to eq Fixnum
      expect(hash[:purchase_date].class).to eq String
    end
  end
end
