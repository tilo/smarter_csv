require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'chunked reading' do

  it 'loads_chunk_cornercase_csv_files with v1 defaults' do
    (0..6).each do |chunk_size|    # test for all chunk-sizes
      options = {
        :chunk_size => chunk_size,
        :defaults => 'v1'
       }
      data = SmarterCSV.process("#{fixture_path}/chunk_cornercase.csv", options)

      data.flatten.size.should == 5  # end-result must always be 5 rows
    end
  end

  it 'loads_chunk_cornercase_csv_files with safe defaults' do
    (0..6).each do |chunk_size|    # test for all chunk-sizes
      options = {
        :chunk_size => chunk_size,
        :defaults => 'safe'
       }
      data = SmarterCSV.process("#{fixture_path}/chunk_cornercase.csv", options)

      data.flatten.size.should == 5  # end-result must always be 5 rows
    end
  end

  it 'loads_chunk_cornercase_csv_files' do
    (0..6).each do |chunk_size|    # test for all chunk-sizes
      options = {
        :chunk_size => chunk_size,
        :hash_transformations => [ :remove_blank_values ]
       }
      data = SmarterCSV.process("#{fixture_path}/chunk_cornercase.csv", options)

      data.flatten.size.should == 5  # end-result must always be 5 rows
    end
  end

end
