require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be_able_to' do
  it 'loads_basic_csv_file' do 
    data = SmarterCSV.process("#{fixture_path}/basic.csv")
    expect(data.size).to eq 5

    # all the keys should be symbols
    data.each{|item| item.keys.each{|x| expect(x).to be_instance_of(Symbol)}}
    data.each do |h|
      h.keys.each do |key|
        expect([:first_name, :last_name, :dogs, :cats, :birds, :fish]).to include(key)
      end
      expect(h.size).to be <= 6
    end
  end

end
