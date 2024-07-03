# frozen_string_literal: true

describe 'blank?' do
  let(:reader) { SmarterCSV::Reader.new('/tmp/fake.csv') }

  it 'is true for nil' do
    expect(reader.send(:blank?, nil)).to eq true
  end

  it 'is true for empty string' do
    expect(reader.send(:blank?, '')).to eq true
  end

  it 'is true for blank string' do
    expect(reader.send(:blank?, '   ')).to eq true
  end

  it 'is true for tab string' do
    expect(reader.send(:blank?, " \t ")).to eq true
  end

  it 'is false for string with content' do
    expect(reader.send(:blank?, " 1 ")).to eq false
  end

  it 'is false for numeic values' do
    expect(reader.send(:blank?, 1)).to eq false
  end

  describe 'arrays' do
    it 'is true for empty arrays' do
      expect(reader.send(:blank?, [])).to eq true
    end

    it 'is true for blank arrays' do
      expect(reader.send(:blank?, [nil, '', '  ', " \t "])).to eq true
    end

    it 'is false for non-blank arrays' do
      expect(reader.send(:blank?, [nil, '', '  ', " 1 "])).to eq false
    end
  end

  describe 'hashes' do
    it 'is true for empty arrays' do
      expect(reader.send(:blank?, {})).to eq true
    end

    it 'is true for blank arrays' do
      expect(reader.send(:blank?, {a: nil, b: '', c: '  ', d: " \t "})).to eq true
    end

    it 'is false for non-blank arrays' do
      expect(reader.send(:blank?, {a: nil, b: '', c: '  ', d: " 1 "})).to eq false
    end
  end
end
