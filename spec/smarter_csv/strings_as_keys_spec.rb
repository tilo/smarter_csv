require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be_able_to' do
  it 'use_strings_as_keys' do 
    options = {:strings_as_keys => true}
    data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
    expect(data.size).to eq(5)
    # all the keys should be symbols
    data.each{|item| item.keys.each{|x| expect(x).to be_instance_of(String)}}

    data.each do |item| 
      item.keys.each do |key|
        expect(["first_name", "last_name", "dogs", "cats", "birds", "fish"]).to include(key)
      end
    end

    data.each do |h|
      expect(h.size).to be <= 6
    end
  end

end
