# frozen_string_literal: true

require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'modify headers' do
  it 'rename some headers with v1 defaults' do
    options = {
      defaults: 'v1',
      header_transformations: [key_mapping: {first_name: :vorname, last_name: :nachname}]
    }
    data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
    data.size.should eq 5

    data.each do |hash|
      hash.each_key do |key|
        key.class.should eq Symbol
        [:vorname, :nachname, :dogs, :cats, :birds, :fish].should include(key)
      end
      hash.values.should_not include(nil) # v1 defaults should remove blank values
      hash.size.should <= 6
    end
  end

  it 'rename some headers with new defaults' do
    options = {
      header_transformations: [key_mapping: {first_name: :vorname, last_name: :nachname}]
    }
    data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
    data.size.should eq 5

    data.each do |hash|
      hash.each_key do |key|
        key.class.should eq Symbol
        [:vorname, :nachname, :dogs, :cats, :birds, :fish].should include(key)
      end
      hash.values.should_not include(nil) # safe defaults should remove blank values
      hash.size.should <= 6
    end
  end

  it 'remove fields by mapping them to nil' do
    options = {
      header_transformations: [key_mapping: {first_name: :vorname, last_name: :nachname, birds: nil, fish: nil, dogs: nil, cats: nil}]
    }
    data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
    data.size.should eq 5

    data.each do |hash|
      hash.each_key do |key|
        key.class.should eq Symbol
        [:vorname, :nachname].should include(key)
        [:dogs, :cats, :birds, :fish].should_not include(key)
      end
      hash.values.should_not include(nil) # safe defaults should remove blank values
      hash.size.should eq 2
    end
  end
end
