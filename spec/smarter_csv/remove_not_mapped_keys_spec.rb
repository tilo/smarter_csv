require 'spec_helper'

fixture_path = 'spec/fixtures'

describe ':remove_unmapped_keys option' do

  it 'it has no effect on loading a file without options' do 
  	options = {}
    data = SmarterCSV.process("#{fixture_path}/lots_of_columns.csv", options)
    data.size.should eq 1
    data.first.size.should eq 474 # there are some empty rows in the fixture
  end

  it 'it has no effect if provided without :key_mapping' do
  	options = {:remove_unmapped_keys => true}
    data = SmarterCSV.process("#{fixture_path}/lots_of_columns.csv", options)
    data.size.should eq 1
    data.first.size.should eq 474 # there are some empty rows in the fixture
  end

  it 'it defaults to false and has no effect if :key_mapping is provided without :remove_unmapped_keys' do
  	options = {:key_mapping => {:column_0 => :one, :column_15 => :two, :column_42 => :three}}
    data = SmarterCSV.process("#{fixture_path}/lots_of_columns.csv", options)
    data.size.should eq 1
    data.first.size.should eq 474 # there are some empty rows in the fixture
  end

  it 'it removes non-mapped keys/columns when set to true and :key_mapping is provided' do 
  	options = {:remove_unmapped_keys => true, :key_mapping => {:column_0 => :one, :column_15 => :two, :column_42 => :three}}
    data = SmarterCSV.process("#{fixture_path}/lots_of_columns.csv", options)
    data.size.should eq 1
    data.first.size.should eq 2 # column_15 is empty
  end
end

