require 'spec_helper'

describe 'misc functionality' do

  describe 'elem_blank?' do
    it 'returns true for nil' do
      expect( SmarterCSV.send(:elem_blank?, nil)).to eq true
    end

    it 'returns true for ""' do
      expect( SmarterCSV.send(:elem_blank?, "")).to eq true
    end

    it 'returns true for "\t \r\n\t"' do
      expect( SmarterCSV.send(:elem_blank?, "\t \r\n\t")).to eq true
    end

    it 'returns false for "a"' do
      expect( SmarterCSV.send(:elem_blank?, "a")).to eq false
    end

    it 'returns false for 1234' do
      expect( SmarterCSV.send(:elem_blank?, 1234)).to eq false
    end
  end
end
