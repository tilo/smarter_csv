require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be_able_to' do

  class DummyConverter
    def self.convert(value)
      value.reverse
    end
  end

  it 'convert values for given keys' do
    options = { :value_converters => { :first_name => DummyConverter } }
    data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
    not_converted_data = SmarterCSV.process("#{fixture_path}/basic.csv")


    data.each_with_index { |d,i| d[:first_name].should eq not_converted_data[i][:first_name].reverse }
  end
end
