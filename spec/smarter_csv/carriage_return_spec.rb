require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'process files' do

  let!(:options) {{}}

  describe 'with line endings explicitly pre-specified' do

    it 'should process a file with \n for line endings and within data fields' do
      sep = "\n"
      options.merge!( { row_sep: sep } )

      data = SmarterCSV.process("#{fixture_path}/carriage_returns_n.csv", options)

      data.flatten.size.should eq 8
      data[0][:name].should eq "Anfield"
      data[0][:street].should eq "Anfield Road"
      data[0][:city].should eq "Liverpool"
      data[1][:name].should eq ["Highbury", "Highbury House"].join(sep)
      data[2][:street].should eq ["Sir Matt ", "Busby Way"].join(sep)
      data[3][:city].should eq ["Newcastle-upon-tyne ", "Tyne and Wear"].join(sep)
      data[4][:name].should eq ["White Hart Lane", "(The Lane)"].join(sep)
      data[4][:street].should eq ["Bill Nicholson Way ", "748 High Rd"].join(sep)
      data[4][:city].should eq ["Tottenham", "London"].join(sep)
      data[5][:name].should eq "Stamford Bridge"
      data[5][:street].should eq ["Fulham Road", "London"].join(sep)
      data[5][:city].should be_nil
      data[6][:name].should eq ["Etihad Stadium", "Rowsley St", "Manchester"].join(sep)
      data[7][:name].should eq "Goodison"
      data[7][:street].should eq "Goodison Road"
      data[7][:city].should eq "Liverpool"
    end

    it 'should process a file with \r for line endings and within data fields' do
      sep = "\r"
      options.merge!( { row_sep: sep } )

      data = SmarterCSV.process("#{fixture_path}/carriage_returns_r.csv", options)

      data.flatten.size.should eq 8
      data[0][:name].should eq "Anfield"
      data[0][:street].should eq "Anfield Road"
      data[0][:city].should eq "Liverpool"
      data[1][:name].should eq ["Highbury", "Highbury House"].join(sep)
      data[2][:street].should eq ["Sir Matt ", "Busby Way"].join(sep)
      data[3][:city].should eq ["Newcastle-upon-tyne ", "Tyne and Wear"].join(sep)
      data[4][:name].should eq ["White Hart Lane", "(The Lane)"].join(sep)
      data[4][:street].should eq ["Bill Nicholson Way ", "748 High Rd"].join(sep)
      data[4][:city].should eq ["Tottenham", "London"].join(sep)
      data[5][:name].should eq "Stamford Bridge"
      data[5][:street].should eq ["Fulham Road", "London"].join(sep)
      data[5][:city].should be_nil
      data[6][:name].should eq ["Etihad Stadium", "Rowsley St", "Manchester"].join(sep)
      data[7][:name].should eq "Goodison"
      data[7][:street].should eq "Goodison Road"
      data[7][:city].should eq "Liverpool"
    end

    it 'should process a file with \r\n for line endings and within data fields' do
      sep = "\r\n"
      options.merge!( { row_sep: sep } )

      data = SmarterCSV.process("#{fixture_path}/carriage_returns_rn.csv", options)

      data.flatten.size.should eq 8
      data[0][:name].should eq "Anfield"
      data[0][:street].should eq "Anfield Road"
      data[0][:city].should eq "Liverpool"
      data[1][:name].should eq ["Highbury", "Highbury House"].join(sep)
      data[2][:street].should eq ["Sir Matt ", "Busby Way"].join(sep)
      data[3][:city].should eq ["Newcastle-upon-tyne ", "Tyne and Wear"].join(sep)
      data[4][:name].should eq ["White Hart Lane", "(The Lane)"].join(sep)
      data[4][:street].should eq ["Bill Nicholson Way ", "748 High Rd"].join(sep)
      data[4][:city].should eq ["Tottenham", "London"].join(sep)
      data[5][:name].should eq "Stamford Bridge"
      data[5][:street].should eq ["Fulham Road", "London"].join(sep)
      data[5][:city].should be_nil
      data[6][:name].should eq ["Etihad Stadium", "Rowsley St", "Manchester"].join(sep)
      data[7][:name].should eq "Goodison"
      data[7][:street].should eq "Goodison Road"
      data[7][:city].should eq "Liverpool"
    end

    it 'should process a file with more quoted text carriage return characters (\r) than line ending characters (\n)' do
      row_sep = "\n"
      text_sep = "\r"
      options.merge!( { row_sep: row_sep } )

      data = SmarterCSV.process("#{fixture_path}/carriage_returns_quoted.csv", options)

      data.flatten.size.should eq 2
      data[0][:band].should eq "New Order"
      data[0][:members].should eq ["Bernard Sumner", "Peter Hook", "Stephen Morris", "Gillian Gilbert"].join(text_sep)
      data[0][:albums].should eq ["Movement", "Power, Corruption and Lies", "Low-Life", "Brotherhood", "Substance"].join(text_sep)
      data[1][:band].should eq "Led Zeppelin"
      data[1][:members].should eq ["Jimmy Page", "Robert Plant", "John Bonham", "John Paul Jones"].join(text_sep)
      data[1][:albums].should eq ["Led Zeppelin", "Led Zeppelin II", "Led Zeppelin III", "Led Zeppelin IV"].join(text_sep)
    end

  end

  describe 'with line endings in automatic mode' do

    it 'should process a file with \n for line endings and within data fields' do
      sep = "\n"
      options.merge!( { row_sep: :auto } )

      data = SmarterCSV.process("#{fixture_path}/carriage_returns_n.csv", options)

      data.flatten.size.should eq 8
      data[0][:name].should eq "Anfield"
      data[0][:street].should eq "Anfield Road"
      data[0][:city].should eq "Liverpool"
      data[1][:name].should eq ["Highbury", "Highbury House"].join(sep)
      data[2][:street].should eq ["Sir Matt ", "Busby Way"].join(sep)
      data[3][:city].should eq ["Newcastle-upon-tyne ", "Tyne and Wear"].join(sep)
      data[4][:name].should eq ["White Hart Lane", "(The Lane)"].join(sep)
      data[4][:street].should eq ["Bill Nicholson Way ", "748 High Rd"].join(sep)
      data[4][:city].should eq ["Tottenham", "London"].join(sep)
      data[5][:name].should eq "Stamford Bridge"
      data[5][:street].should eq ["Fulham Road", "London"].join(sep)
      data[5][:city].should be_nil
      data[6][:name].should eq ["Etihad Stadium", "Rowsley St", "Manchester"].join(sep)
      data[7][:name].should eq "Goodison"
      data[7][:street].should eq "Goodison Road"
      data[7][:city].should eq "Liverpool"
    end

    it 'should process a file with \r for line endings and within data fields' do
      sep = "\r"
      options.merge!( { row_sep: :auto } )

      data = SmarterCSV.process("#{fixture_path}/carriage_returns_r.csv", options)

      data.flatten.size.should eq 8
      data[0][:name].should eq "Anfield"
      data[0][:street].should eq "Anfield Road"
      data[0][:city].should eq "Liverpool"
      data[1][:name].should eq ["Highbury", "Highbury House"].join(sep)
      data[2][:street].should eq ["Sir Matt ", "Busby Way"].join(sep)
      data[3][:city].should eq ["Newcastle-upon-tyne ", "Tyne and Wear"].join(sep)
      data[4][:name].should eq ["White Hart Lane", "(The Lane)"].join(sep)
      data[4][:street].should eq ["Bill Nicholson Way ", "748 High Rd"].join(sep)
      data[4][:city].should eq ["Tottenham", "London"].join(sep)
      data[5][:name].should eq "Stamford Bridge"
      data[5][:street].should eq ["Fulham Road", "London"].join(sep)
      data[5][:city].should be_nil
      data[6][:name].should eq ["Etihad Stadium", "Rowsley St", "Manchester"].join(sep)
      data[7][:name].should eq "Goodison"
      data[7][:street].should eq "Goodison Road"
      data[7][:city].should eq "Liverpool"
    end

    it 'should process a file with \r\n for line endings and within data fields' do
      sep = "\r\n"
      options.merge!( { row_sep: :auto } )

      data = SmarterCSV.process("#{fixture_path}/carriage_returns_rn.csv", options)

      data.flatten.size.should eq 8
      data[0][:name].should eq "Anfield"
      data[0][:street].should eq "Anfield Road"
      data[0][:city].should eq "Liverpool"
      data[1][:name].should eq ["Highbury", "Highbury House"].join(sep)
      data[2][:street].should eq ["Sir Matt ", "Busby Way"].join(sep)
      data[3][:city].should eq ["Newcastle-upon-tyne ", "Tyne and Wear"].join(sep)
      data[4][:name].should eq ["White Hart Lane", "(The Lane)"].join(sep)
      data[4][:street].should eq ["Bill Nicholson Way ", "748 High Rd"].join(sep)
      data[4][:city].should eq ["Tottenham", "London"].join(sep)
      data[5][:name].should eq "Stamford Bridge"
      data[5][:street].should eq ["Fulham Road", "London"].join(sep)
      data[5][:city].should be_nil
      data[6][:name].should eq ["Etihad Stadium", "Rowsley St", "Manchester"].join(sep)
      data[7][:name].should eq "Goodison"
      data[7][:street].should eq "Goodison Road"
      data[7][:city].should eq "Liverpool"
    end

    it 'should process a file with more quoted text carriage return characters (\r) than line ending characters (\n)' do
      row_sep = "\n"
      text_sep = "\r"
      options.merge!( { row_sep: :auto } )

      data = SmarterCSV.process("#{fixture_path}/carriage_returns_quoted.csv", options)

      data.flatten.size.should eq 2
      data[0][:band].should eq "New Order"
      data[0][:members].should eq ["Bernard Sumner", "Peter Hook", "Stephen Morris", "Gillian Gilbert"].join(text_sep)
      data[0][:albums].should eq ["Movement", "Power, Corruption and Lies", "Low-Life", "Brotherhood", "Substance"].join(text_sep)
      data[1][:band].should eq "Led Zeppelin"
      data[1][:members].should eq ["Jimmy Page", "Robert Plant", "John Bonham", "John Paul Jones"].join(text_sep)
      data[1][:albums].should eq ["Led Zeppelin", "Led Zeppelin II", "Led Zeppelin III", "Led Zeppelin IV"].join(text_sep)
    end
  end
end
