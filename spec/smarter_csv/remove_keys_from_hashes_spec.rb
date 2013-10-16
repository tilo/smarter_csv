require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be_able_to' do
  it 'remove_values_matching' do 
    options = {:remove_zero_values => true, :key_mapping => {:first_name => :vorname, :last_name => :nachname, :fish => nil} }
    data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
    data.size.should == 5
    # all the keys should be symbols
    data.each{|item| item.keys.each{|x| x.class.should be == Symbol}}

    data.each do |hash| 
      hash.keys.each do |key|
        [:vorname, :nachname, :dogs, :cats, :birds].should include( key )
      end
      hash.values.should_not include( 0 )
    end

    data.each do |h|
      h.size.should <= 6
    end
  end

end
