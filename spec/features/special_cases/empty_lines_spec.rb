# frozen_string_literal: true

fixture_path = 'spec/fixtures'

describe 'loading a completely empty file' do
  it 'raises EmptyFileError' do
    require 'tempfile'
    t = Tempfile.new('smarter_csv_empty')
    t.close
    expect { SmarterCSV.process(t.path) }.to raise_error(SmarterCSV::EmptyFileError, /Empty CSV file/)
    t.unlink
  end
end

[true, false].each do |bool|
  describe "loading file with empty lines with#{bool ? ' C-' : 'out '}acceleration" do
    let(:options) { { acceleration: bool } }

    it 'loads the data correctly' do
      data = SmarterCSV.process("#{fixture_path}/empty_lines.csv", options)

      expect(data.length).to eq 2

      expect(data[0]).to eq({id: 1, name: 'Bob'})
      expect(data[1]).to eq({id: 2, name: 'Paul'})
    end
  end
end
