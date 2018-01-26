require 'spec_helper'

fixture_path = 'spec/fixtures'

# somebody reported that a column called 'options_trader' would be truncated to 'trader'

describe 'loads simple file format' do

  it 'with symbols as keys when using defaults' do
    options = {}
    data = SmarterCSV.process("#{fixture_path}/trading.csv", options)

    data.flatten.size.should eq 2
    data.each do |item|
      # all keys should be symbols when using v1.x backwards compatible mode
      item.keys.each{|x| x.class.should eq Symbol}
      item[:account_id].class.should eq Fixnum
      item[:options_trader].class.should eq String
      item[:stock_symbol].class.should eq String
      item[:shares_issued].class.should eq Fixnum
      item[:purchase_date].class.should eq String
    end
  end

end
