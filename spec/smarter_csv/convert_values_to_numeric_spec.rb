require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'numeric conversion of values' do
  it 'occurs by default' do
    options = {}
    data = SmarterCSV.process("#{fixture_path}/numeric.csv", options)
    expect(data.size).to eq(3)
    
    # all the keys should be symbols
    data.each do |hash|
      expect(hash[:wealth]).to be_kind_of(Numeric) unless hash[:wealth].nil?
      expect(hash[:reference]).to be_kind_of(Numeric) unless hash[:reference].nil?
    end
  end

  it 'can be prevented for all values' do
    options = { :convert_values_to_numeric => false }
    data = SmarterCSV.process("#{fixture_path}/numeric.csv", options)
    
    data.each do |hash|
      expect(hash[:wealth]).to be_instance_of(String) unless hash[:wealth].nil?
      expect(hash[:reference]).to be_instance_of(String) unless hash[:reference].nil?
    end
  end

  it 'can be prevented for some keys' do
    options = { :convert_values_to_numeric => { :except => :reference }}
    data = SmarterCSV.process("#{fixture_path}/numeric.csv", options)

    data.each do |hash|
      expect(hash[:wealth]).to be_kind_of(Numeric) unless hash[:wealth].nil?
      expect(hash[:reference]).to be_instance_of(String) unless hash[:reference].nil?
    end
  end
  
  it 'can occur only for some keys' do
    options = { :convert_values_to_numeric => { :only => :wealth }}
    data = SmarterCSV.process("#{fixture_path}/numeric.csv", options)

    data.each do |hash|
      expect(hash[:wealth]).to be_kind_of(Numeric) unless hash[:wealth].nil?
      expect(hash[:reference]).to be_instance_of(String) unless hash[:reference].nil?
    end
  end
end

