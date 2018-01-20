require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'test exceptions for invalid headers' do
  it 'raises error on duplicate headers' do
    expect {
      SmarterCSV.process("#{fixture_path}/duplicate_headers.csv", {})
    }.to raise_exception(SmarterCSV::DuplicateHeaders)
  end

  it 'raises error on duplicate given headers' do
    expect {
      options = {:user_provided_headers => [:a,:b,:c,:d,:a]}
      SmarterCSV.process("#{fixture_path}/duplicate_headers.csv", options)
    }.to raise_exception(SmarterCSV::DuplicateHeaders)
  end

  it 'raises error on duplicate mapped headers' do
    expect {
      # the mapping is right, but the underlying csv file is bad
      options = {:key_mapping => {:email => :a, :firstname => :b, :lastname => :c, :manager_email => :d, :age => :e} }
      SmarterCSV.process("#{fixture_path}/duplicate_headers.csv", options)
    }.to raise_exception(SmarterCSV::DuplicateHeaders)
  end


  it 'does not raise an error if no required headers are given' do
    options = {:required_headers => nil} # order does not matter
    data = SmarterCSV.process("#{fixture_path}/user_import.csv", options)
    data.size.should eq 2
  end

  it 'does not raise an error if no required headers are given' do
    options = {:required_headers => []} # order does not matter
    data = SmarterCSV.process("#{fixture_path}/user_import.csv", options)
    data.size.should eq 2
  end

  it 'does not raise an error if the required headers are present' do
    options = {:required_headers => [:lastname,:email,:firstname,:manager_email]} # order does not matter
    data = SmarterCSV.process("#{fixture_path}/user_import.csv", options)
    data.size.should eq 2
  end

  it 'raises an error if a required header is missing' do
    expect {
      options = {:required_headers => [:lastname,:email,:employee_id,:firstname,:manager_email]} # order does not matter
      SmarterCSV.process("#{fixture_path}/user_import.csv", options)
    }.to raise_exception(SmarterCSV::MissingHeaders)
  end
end
