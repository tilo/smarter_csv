require 'spec_helper'

fixture_path = 'spec/fixtures'

# this reads a binary database dump file, which is in structure like a CSV file
# but contains control characters delimiting the rows and columns, and also 
# contains a comment section which is commented our by a leading # character

# same as binary_file_spec , but reading the file with strings as keys

describe 'be_able_to' do
  it 'loads_binary_file_with_strings_as_keys' do 
    options = {:col_sep => "\cA", :row_sep => "\cB", :comment_regexp => /^#/, :strings_as_keys => true}
    data = SmarterCSV.process("#{fixture_path}/binary.csv", options)
    expect(data.flatten.size).to eq(8)
    data.each do |item|
      # all keys should be strings
      item.keys.each{|x| expect(x).to be_instance_of(String)}
      expect(item['timestamp']).to eq(1381388409)
      expect(item['item_id']).to be_instance_of(Fixnum)
      expect(item['name'].size).to be > 0
    end
  end
end
