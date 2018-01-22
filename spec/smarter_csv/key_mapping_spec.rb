require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'modify headers' do

  it 'rename some headers with v1 defaults' do
    options = {
      :defaults => 'v1',
      :header_transformations => [ :key_mapping => {:first_name => :vorname, :last_name => :nachname} ]
    }
    data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
    data.size.should == 5
    # all the keys should be symbols
    data.each{|item| item.keys.each{|x| x.class.should eq Symbol}}

    data.each do |hash|
      hash.keys.each do |key|
        [:vorname, :nachname, :dogs, :cats, :birds, :fish].should include( key )
      end
      hash.values.should_not include( nil ) # v1 defaults should remove blank values
    end

    data.each do |h|
      h.size.should <= 6
    end
  end

  it 'rename some headers with safe defaults' do
    options = {
      :defaults => 'safe',
      :header_transformations => [ :key_mapping => {:first_name => :vorname, :last_name => :nachname} ]
    }
    data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
    data.size.should == 5
    # all the keys should be symbols
    data.each{|item| item.keys.each{|x| x.class.should eq Symbol}}

    data.each do |hash|
      hash.keys.each do |key|
        [:vorname, :nachname, :dogs, :cats, :birds, :fish].should include( key )
      end
      hash.values.should_not include( nil ) # safe defaults should remove blank values
    end

    data.each do |h|
      h.size.should <= 6
    end
  end

  it 'rename some headers' do
    options = {
      :header_transformations => [ :keys_as_symbols, :key_mapping => {:first_name => :vorname, :last_name => :nachname} ]
    }
    data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
    data.size.should == 5
    # all the keys should be symbols
    data.each{|item| item.keys.each{|x| x.class.should eq Symbol}}

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

end
