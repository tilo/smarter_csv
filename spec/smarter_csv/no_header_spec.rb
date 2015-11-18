require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be_able_to' do
  it 'loads_csv_file_without_header' do 
    options = {:headers_in_file => false, :user_provided_headers => [:a,:b,:c,:d,:e,:f]}
    data = SmarterCSV.process("#{fixture_path}/no_header.csv", options)
    expect(data.size).to eq(5)
    # all the keys should be symbols
    data.each{|item| item.keys.each{|x| expect(x).to be_instance_of(Symbol)}}

    data.each do |item| 
      item.keys.each do |key|
        expect([:a,:b,:c,:d,:e,:f]).to include(key)
      end
    end

    data.each do |h|
      expect(h.size).to be <= 6
    end
  end

end
