require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'breaks no bad input if multiline is not specified' do

  subject { lambda { SmarterCSV.process(csv_path, {:multiline  => false}) } }
  context "it breaks on malformed content if multiline was not specified" do
    let(:csv_path) { "#{fixture_path}/carriage_returns_n.csv" }
    it { should raise_error(SmarterCSV::MalformedCSVError) }
  end

end

describe 'process files with line endings explicitly pre-specified' do
  let(:options){ {:multiline => true}}

  it 'should process a file with \n for line endings and within data fields' do
    sep = "\n"
    data = SmarterCSV.process("#{fixture_path}/carriage_returns_n.csv", options.merge({:row_sep => sep}))
    data.flatten.size.should == 8
    data[0][:name].should == "Anfield"
    data[0][:street].should == "Anfield Road"
    data[0][:city].should == "Liverpool"
    data[1][:name].should == ["Highbury", "Highbury House"].join(sep)
    data[2][:street].should == ["Sir Matt ", "Busby Way"].join(sep)
    data[3][:city].should == ["Newcastle-upon-tyne ", "Tyne and Wear"].join(sep)
    data[4][:name].should == ["White Hart Lane", "(The Lane)"].join(sep)
    data[4][:street].should == ["Bill Nicholson Way ", "748 High Rd"].join(sep)
    data[4][:city].should == ["Tottenham", "London"].join(sep)
    data[5][:name].should == "Stamford Bridge"
    data[5][:street].should == ["Fulham Road", "London"].join(sep)
    data[5][:city].should be_nil
    data[6][:name].should == ["Etihad Stadium", "Rowsley St", "Manchester"].join(sep)
    data[7][:name].should == "Goodison"
    data[7][:street].should == "Goodison Road"
    data[7][:city].should == "Liverpool"
  end

  it 'should process a file with \r for line endings and within data fields' do
    sep = "\r"
    data = SmarterCSV.process("#{fixture_path}/carriage_returns_r.csv", options.merge({:row_sep => sep}))
    data.flatten.size.should == 8
    data[0][:name].should == "Anfield"
    data[0][:street].should == "Anfield Road"
    data[0][:city].should == "Liverpool"
    data[1][:name].should == ["Highbury", "Highbury House"].join(sep)
    data[2][:street].should == ["Sir Matt ", "Busby Way"].join(sep)
    data[3][:city].should == ["Newcastle-upon-tyne ", "Tyne and Wear"].join(sep)
    data[4][:name].should == ["White Hart Lane", "(The Lane)"].join(sep)
    data[4][:street].should == ["Bill Nicholson Way ", "748 High Rd"].join(sep)
    data[4][:city].should == ["Tottenham", "London"].join(sep)
    data[5][:name].should == "Stamford Bridge"
    data[5][:street].should == ["Fulham Road", "London"].join(sep)
    data[5][:city].should be_nil
    data[6][:name].should == ["Etihad Stadium", "Rowsley St", "Manchester"].join(sep)
    data[7][:name].should == "Goodison"
    data[7][:street].should == "Goodison Road"
    data[7][:city].should == "Liverpool"
  end

  it 'should process a file with \r\n for line endings and within data fields' do
    sep = "\r\n"
    data = SmarterCSV.process("#{fixture_path}/carriage_returns_rn.csv", options.merge({:row_sep => sep}))
    data.flatten.size.should == 8
    data[0][:name].should == "Anfield"
    data[0][:street].should == "Anfield Road"
    data[0][:city].should == "Liverpool"
    data[1][:name].should == ["Highbury", "Highbury House"].join(sep)
    data[2][:street].should == ["Sir Matt ", "Busby Way"].join(sep)
    data[3][:city].should == ["Newcastle-upon-tyne ", "Tyne and Wear"].join(sep)
    data[4][:name].should == ["White Hart Lane", "(The Lane)"].join(sep)
    data[4][:street].should == ["Bill Nicholson Way ", "748 High Rd"].join(sep)
    data[4][:city].should == ["Tottenham", "London"].join(sep)
    data[5][:name].should == "Stamford Bridge"
    data[5][:street].should == ["Fulham Road", "London"].join(sep)
    data[5][:city].should be_nil
    data[6][:name].should == ["Etihad Stadium", "Rowsley St", "Manchester"].join(sep)
    data[7][:name].should == "Goodison"
    data[7][:street].should == "Goodison Road"
    data[7][:city].should == "Liverpool"
  end

  it 'should process a file with more quoted text carriage return characters (\r) than line ending characters (\n)' do
    row_sep = "\n"
    text_sep = "\r"
    data = SmarterCSV.process("#{fixture_path}/carriage_returns_quoted.csv", options.merge({:row_sep => row_sep}))
    data.flatten.size.should == 2
    data[0][:band].should == "New Order"
    data[0][:members].should == ["Bernard Sumner", "Peter Hook", "Stephen Morris", "Gillian Gilbert"].join(text_sep)
    data[0][:albums].should == ["Movement", "Power, Corruption and Lies", "Low-Life", "Brotherhood", "Substance"].join(text_sep)
    data[1][:band].should == "Led Zeppelin"
    data[1][:members].should == ["Jimmy Page", "Robert Plant", "John Bonham", "John Paul Jones"].join(text_sep)
    data[1][:albums].should == ["Led Zeppelin", "Led Zeppelin II", "Led Zeppelin III", "Led Zeppelin IV"].join(text_sep)
  end

end

describe 'process files with line endings in automatic mode' do
  let(:options){ {:multiline => true}}
  it 'should process a file with \n for line endings and within data fields' do
    sep = "\n"
    data = SmarterCSV.process("#{fixture_path}/carriage_returns_n.csv", options.merge({:row_sep => :auto}))
    data.flatten.size.should == 8
    data[0][:name].should == "Anfield"
    data[0][:street].should == "Anfield Road"
    data[0][:city].should == "Liverpool"
    data[1][:name].should == ["Highbury", "Highbury House"].join(sep)
    data[2][:street].should == ["Sir Matt ", "Busby Way"].join(sep)
    data[3][:city].should == ["Newcastle-upon-tyne ", "Tyne and Wear"].join(sep)
    data[4][:name].should == ["White Hart Lane", "(The Lane)"].join(sep)
    data[4][:street].should == ["Bill Nicholson Way ", "748 High Rd"].join(sep)
    data[4][:city].should == ["Tottenham", "London"].join(sep)
    data[5][:name].should == "Stamford Bridge"
    data[5][:street].should == ["Fulham Road", "London"].join(sep)
    data[5][:city].should be_nil
    data[6][:name].should == ["Etihad Stadium", "Rowsley St", "Manchester"].join(sep)
    data[7][:name].should == "Goodison"
    data[7][:street].should == "Goodison Road"
    data[7][:city].should == "Liverpool"
  end

  it 'should process a file with \r for line endings and within data fields' do
    sep = "\r"
    data = SmarterCSV.process("#{fixture_path}/carriage_returns_r.csv", options.merge({:row_sep => :auto}))
    data.flatten.size.should == 8
    data[0][:name].should == "Anfield"
    data[0][:street].should == "Anfield Road"
    data[0][:city].should == "Liverpool"
    data[1][:name].should == ["Highbury", "Highbury House"].join(sep)
    data[2][:street].should == ["Sir Matt ", "Busby Way"].join(sep)
    data[3][:city].should == ["Newcastle-upon-tyne ", "Tyne and Wear"].join(sep)
    data[4][:name].should == ["White Hart Lane", "(The Lane)"].join(sep)
    data[4][:street].should == ["Bill Nicholson Way ", "748 High Rd"].join(sep)
    data[4][:city].should == ["Tottenham", "London"].join(sep)
    data[5][:name].should == "Stamford Bridge"
    data[5][:street].should == ["Fulham Road", "London"].join(sep)
    data[5][:city].should be_nil
    data[6][:name].should == ["Etihad Stadium", "Rowsley St", "Manchester"].join(sep)
    data[7][:name].should == "Goodison"
    data[7][:street].should == "Goodison Road"
    data[7][:city].should == "Liverpool"
  end

  it 'should process a file with \r\n for line endings and within data fields' do
    sep = "\r\n"
    data = SmarterCSV.process("#{fixture_path}/carriage_returns_rn.csv", options.merge({:row_sep => :auto}))
    data.flatten.size.should == 8
    data[0][:name].should == "Anfield"
    data[0][:street].should == "Anfield Road"
    data[0][:city].should == "Liverpool"
    data[1][:name].should == ["Highbury", "Highbury House"].join(sep)
    data[2][:street].should == ["Sir Matt ", "Busby Way"].join(sep)
    data[3][:city].should == ["Newcastle-upon-tyne ", "Tyne and Wear"].join(sep)
    data[4][:name].should == ["White Hart Lane", "(The Lane)"].join(sep)
    data[4][:street].should == ["Bill Nicholson Way ", "748 High Rd"].join(sep)
    data[4][:city].should == ["Tottenham", "London"].join(sep)
    data[5][:name].should == "Stamford Bridge"
    data[5][:street].should == ["Fulham Road", "London"].join(sep)
    data[5][:city].should be_nil
    data[6][:name].should == ["Etihad Stadium", "Rowsley St", "Manchester"].join(sep)
    data[7][:name].should == "Goodison"
    data[7][:street].should == "Goodison Road"
    data[7][:city].should == "Liverpool"
  end

  it 'should process a file with more quoted text carriage return characters (\r) than line ending characters (\n)' do
    row_sep = "\n"
    text_sep = "\r"
    data = SmarterCSV.process("#{fixture_path}/carriage_returns_quoted.csv", options.merge({:row_sep => :auto}))
    data.flatten.size.should == 2
    data[0][:band].should == "New Order"
    data[0][:members].should == ["Bernard Sumner", "Peter Hook", "Stephen Morris", "Gillian Gilbert"].join(text_sep)
    data[0][:albums].should == ["Movement", "Power, Corruption and Lies", "Low-Life", "Brotherhood", "Substance"].join(text_sep)
    data[1][:band].should == "Led Zeppelin"
    data[1][:members].should == ["Jimmy Page", "Robert Plant", "John Bonham", "John Paul Jones"].join(text_sep)
    data[1][:albums].should == ["Led Zeppelin", "Led Zeppelin II", "Led Zeppelin III", "Led Zeppelin IV"].join(text_sep)
  end

end
