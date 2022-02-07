require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be_able_to' do
  it 'remove_values_matching' do 
    options = {:remove_zero_values => true, :key_mapping => {:first_name => :vorname, :last_name => :nachname} }
    data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
    data.size.should == 5
    # all the keys should be symbols
    data.each{|item| item.keys.each{|x| x.class.should be == Symbol}}

    data.each do |hash| 
      hash.keys.each do |key|
        [:vorname, :nachname, :dogs, :cats, :birds, :fish].should include( key )
      end
      hash.values.should_not include( 0 )
    end

    data.each do |h|
      h.size.should <= 6
    end
  end

  describe 'when keep_original_headers' do
    it 'without key mapping' do
      options = {:keep_original_headers => true}
      data = SmarterCSV.process("#{fixture_path}/key_mapping.csv", options)
      data.size.should == 1
      data.first.keys.should == ['THIS', 'THAT', 'other']
    end

    it 'sets key_mapping to a symbol' do
      options = {:keep_original_headers => true, :key_mapping => {'other' => :other}}
      data = SmarterCSV.process("#{fixture_path}/key_mapping.csv", options)
      data.size.should == 1
      data.first.keys.should == ['THIS', 'THAT', :other]
    end

    # this previously would set the key to a symbol :OTHER, which was a bug!
    it 'sets key_mapping to a string' do
      options = {:keep_original_headers => true, :key_mapping => {'other' => 'OTHER'}}
      data = SmarterCSV.process("#{fixture_path}/key_mapping.csv", options)
      data.size.should == 1
      data.first.keys.should == ['THIS', 'THAT', 'OTHER']
    end

    # users now have to explicitly set this to a symbol, or change the expected keys to be strings.
    it 'sets key_mapping to a symbol' do
      options = {:keep_original_headers => true, :key_mapping => {'other' => :OTHER}}
      data = SmarterCSV.process("#{fixture_path}/key_mapping.csv", options)
      data.size.should == 1
      data.first.keys.should == ['THIS', 'THAT', :OTHER]
    end
  end
end
