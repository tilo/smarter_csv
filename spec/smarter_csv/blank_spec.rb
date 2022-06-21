# frozen_string_literal: true

require 'spec_helper'

describe 'blank?' do
  it 'is true for nil' do
    SmarterCSV.send(:blank?, nil).should eq true
  end

  it 'is true for empty string' do
    SmarterCSV.send(:blank?, '').should eq true
  end

  it 'is true for blank string' do
    SmarterCSV.send(:blank?, '   ').should eq true
  end

  it 'is true for tab string' do
    SmarterCSV.send(:blank?, " \t ").should eq true
  end

  it 'is false for string with content' do
    SmarterCSV.send(:blank?, " 1 ").should eq false
  end

  it 'is false for numeic values' do
    SmarterCSV.send(:blank?, 1).should eq false
  end

  describe 'arrays' do
    it 'is true for empty arrays' do
      SmarterCSV.send(:blank?, []).should eq true
    end

    it 'is true for blank arrays' do
      SmarterCSV.send(:blank?, [nil, '', '  ', " \t "]).should eq true
    end

    it 'is false for non-blank arrays' do
      SmarterCSV.send(:blank?, [nil, '', '  ', " 1 "]).should eq false
    end
  end

  describe 'hashes' do
    it 'is true for empty arrays' do
      SmarterCSV.send(:blank?, {}).should eq true
    end

    it 'is true for blank arrays' do
      SmarterCSV.send(:blank?, {a: nil, b: '', c: '  ', d: " \t "}).should eq true
    end

    it 'is false for non-blank arrays' do
      SmarterCSV.send(:blank?, {a: nil, b: '', c: '  ', d: " 1 "}).should eq false
    end
  end
end
