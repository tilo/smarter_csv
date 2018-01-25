require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'numeric conversion of values' do

  it 'is happening when using v1 defaults' do
    options = { defaults: 'v1' }
    data = SmarterCSV.process("#{fixture_path}/numeric.csv", options)
    data.size.should eq 3

    data.each do |hash|
      hash.keys.each do |k|
        k.should be_a(Symbol)
      end
      hash[:wealth].should be_a(Numeric) unless hash[:wealth].nil?
      hash[:reference].should be_a(Numeric) unless hash[:reference].nil?
    end
  end

  it 'is not happening by default' do
    options = {}
    data = SmarterCSV.process("#{fixture_path}/numeric.csv", options)

    data.each do |hash|
      hash.keys.each do |k|
        k.should be_a(Symbol)
      end
      hash[:wealth].should be_a(String) unless hash[:wealth].nil?
      hash[:reference].should be_a(String) unless hash[:reference].nil?
    end
  end

  it 'can be enabled based on string content' do
    options = {
      hash_transformations: [ :convert_values_to_numeric ]
    }
    data = SmarterCSV.process("#{fixture_path}/numeric.csv", options)
    data.size.should eq 3

    # all the keys should be symbols
    data.each do |hash|
      hash[:wealth].should be_a(Numeric) unless hash[:wealth].nil?
      hash[:reference].should be_a(Numeric) unless hash[:reference].nil?
    end
  end

  it 'can be enabled based on string content, leaving strings with leading zeroes' do
    options = {
      hash_transformations: [ :convert_values_to_numeric_unless_leading_zeroes ]
    }
    data = SmarterCSV.process("#{fixture_path}/numeric_leading_zeroes.csv", options)
    data.size.should eq 3

    # all the keys should be symbols
    data.each do |hash|
      hash[:wealth].should be_a(Numeric) unless hash[:wealth].nil?
      hash[:reference].should be_a(String) unless hash[:reference].nil?
    end
  end

  it 'can be enabled for select key/s' do
    options = {
      hash_transformations: [ convert_values_to_numeric: :wealth ]
    }
    data = SmarterCSV.process("#{fixture_path}/numeric_leading_zeroes.csv", options)
    data.size.should eq 3

    data.each do |hash|
      hash[:wealth].should be_a(Numeric) unless hash[:wealth].nil?
      hash[:reference].should be_a(String) unless hash[:reference].nil?
    end
  end

end

