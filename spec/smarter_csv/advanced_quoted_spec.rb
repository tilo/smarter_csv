require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be_able_to' do


  # quoted fields are currently (1.1.0) not handled correctly :(
  # especially quoted fields containing col_sep or row_sep
  #
  # adding this, would mean a re-write and slowing down the parser
  # I could add a new option :quoted_fields => true or auto-detect that issue

  it 'loads files with quoted fields and embedded commas' do
#    options = {:quoted_fields => true}
    data = SmarterCSV.process("#{fixture_path}/advanced_quoted.csv")
    data.flatten.size.should == 2
    data[0][:header1].should eq 'field1, contains the col_sep character'
    data[0][:header2].should eq 'field2'
    data[0][:header3].should eq 'field3'
    data[1][:header1].should eq 'field1 has ""nested quotes"" in it'
    data[1][:header2].should eq 'field2'
    data[1][:header3].should eq 'field3'
  end

  it 'prcesses CSV with malformed hearder' do
    data = SmarterCSV.process( "#{fixture_path}/malformed_header.csv" )
    data.flatten.size.should == 2
    data.first.keys.should eq [:name, :"dob\"dob\""]
  end

  it 'prcesses CSV with malformed body' do
    data = SmarterCSV.process( "#{fixture_path}/malformed.csv" )
    data.flatten.size.should == 2
    data[1][:name].should eq 'Jeff "the dude" Bridges'
  end

  describe 'raises error if CSV body has extra quote char' do
    subject { lambda { SmarterCSV.process(csv_path, {:multiline  => false}) } }

    context "malformed content" do
      let(:csv_path) { "#{fixture_path}/malformed2.csv" }
      it { should raise_error(SmarterCSV::MalformedCSVError) }
    end
  end

  describe 'raises error if CSV body has extra quote char' do
    subject { lambda { SmarterCSV.process(csv_path, {:multiline  => true}) } }

    context "malformed content" do
      let(:csv_path) { "#{fixture_path}/malformed2.csv" }
      it { should raise_error(EOFError) }
    end
  end

end
