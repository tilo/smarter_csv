require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'process files with line endings explicitly pre-specified' do
  it 'reads file with \n line endings' do
    options = {:row_sep => "\n"}
    data = SmarterCSV.process("#{fixture_path}/line_endings_n.csv", options)
    data.size.should == 3
  end

  it 'reads file with \r line endings' do
    options = {:row_sep => "\r"}
    data = SmarterCSV.process("#{fixture_path}/line_endings_r.csv", options)
    data.size.should == 3
   end

  it 'reads file with \r\n line endings' do
    options = {:row_sep => "\r\n"}
    data = SmarterCSV.process("#{fixture_path}/line_endings_rn.csv", options)
    data.size.should == 3
   end
end

describe 'process files with line endings in automatic mode' do
  it 'reads file with \n line endings' do
    options = {:row_sep => :auto}
    data = SmarterCSV.process("#{fixture_path}/line_endings_n.csv", options)
    data.size.should == 3
  end

  it 'reads file with \r line endings' do
    options = {:row_sep => :auto}
    data = SmarterCSV.process("#{fixture_path}/line_endings_r.csv", options)
    data.size.should == 3
   end

  it 'reads file with \r\n line endings' do
    options = {:row_sep => :auto}
    data = SmarterCSV.process("#{fixture_path}/line_endings_rn.csv", options)
    data.size.should == 3
   end
end
