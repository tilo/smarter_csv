require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'numeric conversion of values' do
  it 'occurs by default' do
    options = {}
    data = SmarterCSV.process("#{fixture_path}/numeric.csv", options)
    data.size.should == 3
    
    # all the keys should be symbols
    data.each do |hash|
      hash[:wealth].should be_a_kind_of(Numeric) unless hash[:wealth].nil?
      hash[:reference].should be_a_kind_of(Numeric) unless hash[:reference].nil?
    end
  end

  it 'can be prevented for all values' do
    options = { :convert_values_to_numeric => false }
    data = SmarterCSV.process("#{fixture_path}/numeric.csv", options)
    
    data.each do |hash|
      hash[:wealth].should be_a_kind_of(String) unless hash[:wealth].nil?
      hash[:reference].should be_a_kind_of(String) unless hash[:reference].nil?
    end
  end

  it 'can be prevented for some keys' do
    options = { :convert_values_to_numeric => { :except => :reference }}
    data = SmarterCSV.process("#{fixture_path}/numeric.csv", options)

    data.each do |hash|
      hash[:wealth].should be_a_kind_of(Numeric) unless hash[:wealth].nil?
      hash[:reference].should be_a_kind_of(String) unless hash[:reference].nil?
    end
  end
  
  it 'can occur only for some keys' do
    options = { :convert_values_to_numeric => { :only => :wealth }}
    data = SmarterCSV.process("#{fixture_path}/numeric.csv", options)

    data.each do |hash|
      hash[:wealth].should be_a_kind_of(Numeric) unless hash[:wealth].nil?
      hash[:reference].should be_a_kind_of(String) unless hash[:reference].nil?
    end
  end
end

