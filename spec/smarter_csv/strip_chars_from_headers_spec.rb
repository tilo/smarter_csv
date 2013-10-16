require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be_able_to' do
  it 'strip_whitespace_from_headers' do 
    options = {:strip_chars_from_headers => ' '}
    data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
    data.size.should == 5
    # all the keys should be symbols
    data.each{|item| item.keys.each{|x| x.class.should be == Symbol}}

    data.each do |item| 
      item.keys.each do |key|
        [:firstname, :lastname, :dogs, :cats, :birds, :fish].should include( key )
      end
    end

    data.each do |h|
      h.size.should <= 6
    end
  end

end
