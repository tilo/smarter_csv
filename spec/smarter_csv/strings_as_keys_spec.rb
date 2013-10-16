require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be_able_to' do
  it 'use_strings_as_keys' do 
    options = {:strings_as_keys => true}
    data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
    data.size.should == 5
    # all the keys should be symbols
    data.each{|item| item.keys.each{|x| x.class.should be == String}}

    data.each do |item| 
      item.keys.each do |key|
        ["first_name", "last_name", "dogs", "cats", "birds", "fish"].should include( key )
      end
    end

    data.each do |h|
      h.size.should <= 6
    end
  end

end
