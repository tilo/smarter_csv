require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be_able_to' do
  it 'remove_values_matching' do 
    options = {:remove_zero_values => true, :remove_empty_values => true, :remove_values_matching => /^\d+$/}
    data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
    data.size.should == 5
    # all the keys should be symbols
    data.each{|item| item.keys.each{|x| x.class.should be == Symbol}}

    data.each do |hash| 
      hash.keys.each do |key|
        [:first_name, :last_name].should include( key )
      end
      hash.values.each{|x| x.class.should be == String}
      hash.values.should_not include( 0 )
    end

    data.each do |h|
      h.size.should <= 6
    end
  end

end
