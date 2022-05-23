require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be_able_to' do
  it 'loads_basic_csv_file' do 
    data = SmarterCSV.process("#{fixture_path}/basic.csv")
    data.size.should == 5

    # all the keys should be symbols
    data.each{|item| item.keys.each{|x| x.class.should be == Symbol}}
    data.each do |h|
      h.keys.each do |key|
        [:first_name, :last_name, :dogs, :cats, :birds, :fish].should include( key )
      end
      h.size.should <= 6
    end
  end

  it 'replaces headers with user_provided_headers' do
    options = {user_provided_headers: [:a, :b, :c, :d, :e, :f]}
    data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
    data.size.should == 5

    SmarterCSV.raw_header.should eq "First Name,Last Name,Dogs,Cats,Birds,Fish\n"
    SmarterCSV.headers.should eq [:a, :b, :c, :d, :e, :f]
  end

  it 'raises an exception if the number of user_provided_headers is incorrect' do
    options = {user_provided_headers: [:a, :b, :c, :d, :e]}

    expect {
      SmarterCSV.process("#{fixture_path}/basic.csv", options)
    }.to raise_error(SmarterCSV::HeaderSizeMismatch)
  end
end
