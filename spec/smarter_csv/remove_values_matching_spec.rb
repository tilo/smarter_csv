require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'be_able_to' do
  it 'remove_values_matching' do 
    options = {:remove_zero_values => true, :remove_empty_values => true, :remove_values_matching => /^\d+$/}
    data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
    expect(data.size).to eq(5)
    # all the keys should be symbols
    data.each{|item| item.keys.each{|x| expect(x).to be_instance_of(Symbol)}}

    data.each do |hash| 
      hash.keys.each do |key|
        expect([:first_name, :last_name]).to include( key )
      end
      hash.values.each{|x| expect(x).to be_instance_of(String)}
      expect(hash.values).to_not include(0)
    end

    data.each do |h|
      expect(h.size).to be <= 6
    end
  end

end
