require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be_able_to' do
  it 'not_downcase_headers' do
    options = {:keep_original_headers => true}
    data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
    expect(data.size).to eq(5)
    # all the keys should be string
    data.each{|item| item.keys.each{|x| expect(x).to be_instance_of(String)}}

    data.each do |item|
      item.keys.each do |key|
        expect(['First Name','Last Name','Dogs','Cats','Birds','Fish']).to include(key)
      end
    end

    data.each do |h|
      expect(h.size).to be <= 6
    end
  end

end
