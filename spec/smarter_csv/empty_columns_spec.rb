# frozen_string_literal: true

require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'can handle empty columns' do
  describe 'default behavior' do
    it 'has empty columns at end' do
      data = SmarterCSV.process("#{fixture_path}/empty_columns_1.csv")
      expect(data.size).to eq 1
      item = data.first
      expect(item[:id]).to eq 123
      expect(item[:col1]).to eq nil
      expect(item[:col2]).to eq nil
      expect(item[:col3]).to eq nil
    end

    it 'has empty columns in the middle' do
      data = SmarterCSV.process("#{fixture_path}/empty_columns_2.csv")
      expect(data.size).to eq 1
      item = data.first
      expect(item[:id]).to eq 123
      expect(item[:col1]).to eq nil
      expect(item[:col2]).to eq nil
      expect(item[:col3]).to eq 1
    end
  end

  describe 'with remove_empty_values: true' do
    options = {remove_empty_values: true}
    it 'has empty columns at end' do
      data = SmarterCSV.process("#{fixture_path}/empty_columns_1.csv", options)
      expect(data.size).to eq 1
      item = data.first
      expect(item[:id]).to eq 123
      expect(item[:col1]).to eq nil
      expect(item[:col2]).to eq nil
      expect(item[:col3]).to eq nil
    end

    it 'has empty columns in the middle' do
      data = SmarterCSV.process("#{fixture_path}/empty_columns_2.csv", options)
      expect(data.size).to eq 1
      item = data.first
      expect(item[:id]).to eq 123
      expect(item[:col1]).to eq nil
      expect(item[:col2]).to eq nil
      expect(item[:col3]).to eq 1
    end
  end

  describe 'with remove_empty_values: false' do
    options = {remove_empty_values: false}
    it 'has empty columns at end' do
      data = SmarterCSV.process("#{fixture_path}/empty_columns_1.csv", options)
      expect(data.size).to eq 1
      item = data.first
      expect(item[:id]).to eq 123
      expect(item[:col1]).to eq ''
      expect(item[:col2]).to eq ''
      expect(item[:col3]).to eq ''
    end

    it 'has empty columns in the middle' do
      data = SmarterCSV.process("#{fixture_path}/empty_columns_2.csv", options)
      expect(data.size).to eq 1
      item = data.first
      expect(item[:id]).to eq 123
      expect(item[:col1]).to eq ''
      expect(item[:col2]).to eq ''
      expect(item[:col3]).to eq 1
    end
  end
end
