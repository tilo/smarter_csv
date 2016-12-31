require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be_able_to' do
  it 'remove_values_matching' do 
    options = {:remove_zero_values => true, :key_mapping => {:first_name => :vorname, :last_name => :nachname} }
    data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
    expect(data.size).to eq(5)
    # all the keys should be symbols
    data.each{|item| item.keys.each{|x| expect(x).to be_instance_of(Symbol)}}

    data.each do |hash| 
      hash.keys.each do |key|
        expect([:vorname, :nachname, :dogs, :cats, :birds, :fish]).to include(key)
      end
      expect(hash.values).to_not include(0)
    end

    data.each do |h|
      expect(h.size).to be <= 6
    end
  end

end
