require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'loading file with quoted fields' do

  it 'should work by default, empty strings are replaced by nil, numbers are not converted' do
    options = {header_transformations: :none}
    data = SmarterCSV.process("#{fixture_path}/quoted.csv", options)

    data.flatten.size.should eq 4
    data[1]['Model'].should eq 'Venture "Extended Edition"'
    data[1]['Description'].should be_nil
    data[2]['Model'].should eq 'Venture "Extended Edition, Very Large"'
    data[2]['Description'].should be_nil

    data.each do |h|
      h['Year'].class.should eq String
      h['Make'].should_not be_nil
      h['Model'].should_not be_nil
      h['Price'].class.should eq String
    end
  end

  it 'should work with v1 defaults' do
    options = {:defaults => 'v1'}
    data = SmarterCSV.process("#{fixture_path}/quoted.csv", options)

    data.flatten.size.should eq 4
    data[1][:model].should eq 'Venture "Extended Edition"'
    data[1][:description].should be_nil
    data[2][:model].should eq 'Venture "Extended Edition, Very Large"'
    data[2][:description].should be_nil
    data.each do |h|
      h[:year].class.should eq Fixnum
      h[:make].should_not be_nil
      h[:model].should_not be_nil
      h[:price].class.should eq Float
    end
  end

  it 'should work with safe defaults' do
    options = {}
    data = SmarterCSV.process("#{fixture_path}/quoted.csv", options)

    data.flatten.size.should eq 4
    data[1][:model].should eq 'Venture "Extended Edition"'
    data[1][:description].should be_nil
    data[2][:model].should eq 'Venture "Extended Edition, Very Large"'
    data[2][:description].should be_nil
    data.each do |h|
      h[:year].class.should eq String
      h[:make].should_not be_nil
      h[:model].should_not be_nil
      h[:price].class.should eq String
    end
  end
end
