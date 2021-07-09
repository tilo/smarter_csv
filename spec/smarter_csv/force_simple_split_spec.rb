require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'process badly quoted CSV files' do

  let!(:options) { { col_sep: ';', force_simple_split: true } }

  context 'with single-line raw data CSV file' do
    it 'processes the file ignoring unescaped quotes' do
      data = SmarterCSV.process("#{fixture_path}/unescaped_quotes.csv", options)

      data[0][:make].should eq 'Ford'
      data[0][:model].should eq nil
      data[0][:description].should eq '"ac, "abs", moon"'
      data[1][:make].should eq 'Chevy'
      data[1][:model].should eq 'Venture "Extended Edition""'
      data[1][:description].should eq '""'
      data[2][:make].should eq 'Jeep"'
      data[2][:model].should eq 'Grand "Cherokee'
      data[2][:description].should eq nil
    end
  end
end
