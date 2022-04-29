require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'loading file with quoted fields' do
  it 'leaving the quotes in the data' do
    options = {}
    data = SmarterCSV.process("#{fixture_path}/quoted.csv", options)
    data.flatten.size.should == 4
    data[1][:model].should eq 'Venture "Extended Edition"'
    data[1][:description].should be_nil
    data[2][:model].should eq 'Venture "Extended Edition, Very Large"'
    data[2][:description].should be_nil
    data[3][:description].should eq 'MUST SELL! air, moon roof, loaded'
    data.each do |h|
      h[:year].class.should eq Fixnum
      h[:make].should_not be_nil
      h[:model].should_not be_nil
      h[:price].class.should eq Float
    end
  end

  # quotes inside quoted fields need to be escaped by another double-quote
  it 'removes quotes around quoted fields, but not inside data' do
    options = {}
    data = SmarterCSV.process("#{fixture_path}/quote_char.csv", options)

    data.length.should eq 6
    data[0][:first_name].should eq "\"John"
    data[0][:last_name].should eq "Cooke\""
    data[1][:first_name].should eq "Jam\ne\nson\""
    data[2][:first_name].should eq "\"Jean"
    data[4][:first_name].should eq "Bo\"bbie"
    data[5][:first_name].should eq 'Mica'
    data[5][:last_name].should eq 'Copeland'
  end

  # NOTE: quotes inside headers need to be escaped by doubling them
  #       e.g. 'correct ""EXAMPLE""'
  #       this escaping is illegal: 'incorrect \"EXAMPLE\"' <-- this caused CSV parsing error
  #  in case of CSV parsing errirs, use :user_provided_headers, or key_mapping
  #
  it 'removes quotes around headers and extra quotes inside headers' do
    options = {}
    data = SmarterCSV.process("#{fixture_path}/quoted2.csv", options)

    data.length.should eq 3
    data.first.keys[2].should eq :isbn
    data.first.keys[3].should eq :discounted_price
    data[1][:author].should eq 'Timothy "The Parser" Campbell'
  end
end
