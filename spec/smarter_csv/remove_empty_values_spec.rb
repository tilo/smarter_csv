# frozen_string_literal: true

require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'remove nil values' do
  # when the CSV data is used to update a DB record,
  # there is a difference between setting an attribute to nil,
  # and not modifying the attribute because it's not handed to the update call

  # it seem UNSAFE to zap the value in the DB, just because it did not have a value in the CSV file

  it 'should not remove nil values by default' do
    options = {
      row_sep: :auto,  header_transformations: [:none]
    }
    data = SmarterCSV.process("#{fixture_path}/empty.csv", options)

    data.size.should eq 1
    data[0].keys.should eq ['not empty 1', 'not empty 2', 'not empty 3']
  end

  it 'should work when specifically asked' do
    options = {
      row_sep: :auto,  header_transformations: [:none]
    }
    data = SmarterCSV.process("#{fixture_path}/empty.csv", options)

    data.size.should eq 1
    data[0].keys.should eq ['not empty 1', 'not empty 2', 'not empty 3']
  end

  it 'should work with v1 defaults' do
    options = {row_sep: :auto, defaults: 'v1'}
    data = SmarterCSV.process("#{fixture_path}/empty.csv", options)

    data.size.should eq 1
    data[0].keys.should eq [:not_empty_1, :not_empty_2, :not_empty_3]
  end

  it 'should work with safe default' do
    options = {row_sep: :auto, defaults: 'safe'}
    data = SmarterCSV.process("#{fixture_path}/empty.csv", options)

    data.size.should eq 1
    data[0].keys.should eq [:not_empty_1, :not_empty_2, :not_empty_3]
  end
end
