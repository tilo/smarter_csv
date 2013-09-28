require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be_able_to' do
  it 'loads_chunk_cornercase_csv_files' do 
    (0..5).each do |chunk_size|    # test for all chunk-sizes
      options = {:chunk_size => chunk_size, :remove_empty_hashes => true}
      data = SmarterCSV.process("#{fixture_path}/chunk_cornercase.csv", options)
      data.flatten.size.should == 5  # end-result must always be 5 rows
    end
  end

end
