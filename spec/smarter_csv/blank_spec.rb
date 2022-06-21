# frozen_string_literal: true

require 'spec_helper'

describe 'blank?' do
  it 'is true for nil' do
    expect(SmarterCSV.send(:blank?, nil)).to eq true
  end

  it 'is true for empty string' do
    expect(SmarterCSV.send(:blank?, '')).to eq true
  end

  it 'is true for blank string' do
    expect(SmarterCSV.send(:blank?, '   ')).to eq true
  end

  it 'is true for tab string' do
    expect(SmarterCSV.send(:blank?, " \t ")).to eq true
  end

  it 'is false for string with content' do
    expect(SmarterCSV.send(:blank?, " 1 ")).to eq false
  end

  it 'is false for numeic values' do
    expect(SmarterCSV.send(:blank?, 1)).to eq false
  end

  describe 'arrays' do
    it 'is true for empty arrays' do
      expect(SmarterCSV.send(:blank?, [])).to eq true
    end

    it 'is true for blank arrays' do
      expect(SmarterCSV.send(:blank?, [nil, '', '  ', " \t "])).to eq true
    end

    it 'is false for non-blank arrays' do
      expect(SmarterCSV.send(:blank?, [nil, '', '  ', " 1 "])).to eq false
    end
  end

  describe 'hashes' do
    it 'is true for empty arrays' do
      expect(SmarterCSV.send(:blank?, {})).to eq true
    end

    it 'is true for blank arrays' do
      expect(SmarterCSV.send(:blank?, {a: nil, b: '', c: '  ', d: " \t "})).to eq true
    end

    it 'is false for non-blank arrays' do
      expect(SmarterCSV.send(:blank?, {a: nil, b: '', c: '  ', d: " 1 "})).to eq false
    end
  end
end
