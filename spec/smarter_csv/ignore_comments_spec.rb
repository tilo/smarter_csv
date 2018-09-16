require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be_able_to' do
  it 'ignore comments in CSV files' do
    options = {}
    data = SmarterCSV.process("#{fixture_path}/ignore_comments.csv", options)

    data.size.should eq 5

    # all the keys should be symbols
    data.each{|item| item.keys.each{|x| x.is_a?(Symbol).should be_truthy}}
    data.each do |h|
      h.keys.each do |key|
        [:"not_a_comment#first_name", :last_name, :dogs, :cats, :birds, :fish].should include( key )
      end
    end
  end

  it 'ignore comments in CSV files with CRLF' do
    options = {row_sep: "\r\n"}
    data = SmarterCSV.process("#{fixture_path}/ignore_comments2.csv", options)

    # all the keys should be symbols
    data.size.should eq 1
    data.first[:h1].should eq 'a'
    data.first[:h2].should eq "b\r\n#c"
  end
end
