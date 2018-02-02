require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'remove zero values' do

  it 'does not remove zero values by default' do
    data = SmarterCSV.process("#{fixture_path}/basic.csv")
    data.size.should eq 5

    data.each do |hash|
      hash.keys.each do |key|
        key.class.should eq Symbol  # all the keys should be symbols
        [:first_name, :last_name, :dogs, :cats, :birds, :fish].should include( key )
      end
      hash.values.each do |val|
        val.class.should eq String # no numeric values - no zeros to remove
      end
      hash.size.should <= 6
    end
  end

  it 'removes zeros when specified' do
    options = {
      hash_transformations: [ :remove_zero_values ]
    }
    data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
    data.size.should eq 5

    data.each do |hash|
      hash.keys.each do |key|
        key.class.should eq Symbol
        [:first_name, :last_name, :dogs, :cats, :birds, :fish].should include( key )
      end
      hash.values.should_not include( 0 )
      hash.size.should <= 6
    end
  end

end
