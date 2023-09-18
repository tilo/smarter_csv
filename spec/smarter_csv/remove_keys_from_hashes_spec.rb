# frozen_string_literal: true

require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'removing zero values' do
  it 'does not remove zero values by default' do
    data = SmarterCSV.process("#{fixture_path}/basic.csv")
    data.size.should eq 5

    data.each do |hash|
      hash.each_key do |key|
        key.class.should eq Symbol # all the keys should be symbols
        [:first_name, :last_name, :dogs, :cats, :birds, :fish].should include(key)
      end
      hash.each_value do |val|
        val.class.should eq String # no numeric values - no zeros to remove
      end
      hash.size.should <= 6
    end
  end

  it 'remove_values_matching' do
    options = {
      header_transformations: [key_mapping: {first_name: :vorname, last_name: :nachname, fish: nil}],
      hash_transformations: [:remove_zero_values]
    }
    data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
    data.size.should eq 5

    data.each do |hash|
      hash.each_key do |key|
        key.class.should eq Symbol # all the keys should be symbols
        [:vorname, :nachname, :dogs, :cats, :birds].should include(key)
      end
      hash.values.should_not include(0)
      hash.size.should <= 5
    end
  end
end
