# frozen_string_literal: true

require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'handling of additional trailing column separators' do
  let(:file) { "#{fixture_path}/additional_separator.csv" }

  describe '' do
    let(:data) { SmarterCSV.process(file) }

    it 'reads all lines' do
      data.size.should eq 5
    end

    it 'reads regular lines' do
      item = data[0]
      item[:col1].should == 'eins'
      item[:col2].should == 'zwei'
    end

    it 'strips single trailing col_sep character' do
      item = data[1]
      item[:col1].should == 'uno'
      item[:col2].should == 'dos'
    end

    it 'strips multiple trailing col_sep characters' do
      item = data[2]
      item[:col1].should == 'one'
      item[:col2].should == 'two'
    end

    it 'strips multiple trailing col_sep chars' do
      item = data[3]
      item[:col1].should == 'ichi'
      item[:col2].should == nil
    end

    it 'strips multiple trailing col_sep chars' do
      item = data[4]
      item[:col1].should == 'un'
      item[:col2].should == nil
    end
  end
end
