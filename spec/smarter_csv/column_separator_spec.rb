require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'can handle col_sep' do

  it 'has default of comma as col_sep' do
    data = SmarterCSV.process("#{fixture_path}/separator_comma.csv") # no options
    data.first.keys.size.should == 4
    data.size.should eq 3
  end

  describe 'with explicitly given col_sep' do
    it 'loads file with comma separator' do
      options = {:col_sep => ','}
      data = SmarterCSV.process("#{fixture_path}/separator_comma.csv", options)
      data.first.keys.size.should == 4
      data.size.should eq 3
    end

    it 'loads file with tab separator' do
      options = {:col_sep => "\t"}
      data = SmarterCSV.process("#{fixture_path}/separator_tab.csv", options)
      data.first.keys.size.should == 4
      data.size.should eq 3
    end

    it 'loads file with semi-colon separator' do
      options = {:col_sep => ';'}
      data = SmarterCSV.process("#{fixture_path}/separator_semi.csv", options)
      data.first.keys.size.should == 4
      data.size.should eq 3
    end

    it 'loads file with colon separator' do
      options = {:col_sep => ':'}
      data = SmarterCSV.process("#{fixture_path}/separator_colon.csv", options)
      data.first.keys.size.should == 4
      data.size.should eq 3
    end

    it 'loads file with pipe separator' do
      options = {:col_sep => '|'}
      data = SmarterCSV.process("#{fixture_path}/separator_pipe.csv", options)
      data.first.keys.size.should == 4
      data.size.should eq 3
    end
  end

  describe 'auto-detection of separator' do
    options = {col_sep: :auto}

    it 'auto-detects comma separator and loads data' do
      data = SmarterCSV.process("#{fixture_path}/separator_comma.csv", options)
      data.first.keys.size.should == 4
      data.size.should eq 3
    end

    it 'auto-detects tab separator and loads data' do
      data = SmarterCSV.process("#{fixture_path}/separator_tab.csv", options)
      data.first.keys.size.should == 4
      data.size.should eq 3
    end

    it 'auto-detects semi-colon separator and loads data' do
      data = SmarterCSV.process("#{fixture_path}/separator_semi.csv", options)
      data.first.keys.size.should == 4
      data.size.should eq 3
    end

    it 'auto-detects colon separator and loads data' do
      data = SmarterCSV.process("#{fixture_path}/separator_colon.csv", options)
      data.first.keys.size.should == 4
      data.size.should eq 3
    end

    it 'auto-detects pipe separator and loads data' do
      data = SmarterCSV.process("#{fixture_path}/separator_pipe.csv", options)
      data.first.keys.size.should == 4
      data.size.should eq 3
    end

    it 'does not auto-detect other separators' do
      expect {
        SmarterCSV.process("#{fixture_path}/binary.csv", options)
      }.to raise_exception SmarterCSV::NoColSepDetected
    end

    it 'also works when auto is given a string' do
      data = SmarterCSV.process("#{fixture_path}/separator_pipe.csv", col_sep: 'auto')
      data.first.keys.size.should == 4
      data.size.should eq 3
    end
  end
end
