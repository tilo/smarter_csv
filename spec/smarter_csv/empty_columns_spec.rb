# frozen_string_literal: true

require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'can handle empty columns' do
  describe 'default behavior' do
    it 'has empty columns at end' do
      data = SmarterCSV.process("#{fixture_path}/empty_columns_1.csv")
      data.size.should eq 1
      item = data.first
      item[:id].should == 123
      item[:col1].should == nil
      item[:col2].should == nil
      item[:col3].should == nil
    end

    it 'has empty columns in the middle' do
      data = SmarterCSV.process("#{fixture_path}/empty_columns_2.csv")
      data.size.should eq 1
      item = data.first
      item[:id].should == 123
      item[:col1].should == nil
      item[:col2].should == nil
      item[:col3].should == 1
    end
  end

  describe 'with remove_empty_values: true' do
    options = {remove_empty_values: true}
    it 'has empty columns at end' do
      data = SmarterCSV.process("#{fixture_path}/empty_columns_1.csv", options)
      data.size.should eq 1
      item = data.first
      item[:id].should == 123
      item[:col1].should == nil
      item[:col2].should == nil
      item[:col3].should == nil
    end

    it 'has empty columns in the middle' do
      data = SmarterCSV.process("#{fixture_path}/empty_columns_2.csv", options)
      data.size.should eq 1
      item = data.first
      item[:id].should == 123
      item[:col1].should == nil
      item[:col2].should == nil
      item[:col3].should == 1
    end
  end

  describe 'with remove_empty_values: false' do
    options = {remove_empty_values: false}
    it 'has empty columns at end' do
      data = SmarterCSV.process("#{fixture_path}/empty_columns_1.csv", options)
      data.size.should eq 1
      item = data.first
      item[:id].should == 123
      item[:col1].should == ''
      item[:col2].should == ''
      item[:col3].should == ''
    end

    it 'has empty columns in the middle' do
      data = SmarterCSV.process("#{fixture_path}/empty_columns_2.csv", options)
      data.size.should eq 1
      item = data.first
      item[:id].should == 123
      item[:col1].should == ''
      item[:col2].should == ''
      item[:col3].should == 1
    end
  end
end
