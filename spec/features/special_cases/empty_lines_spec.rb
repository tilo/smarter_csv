# frozen_string_literal: true

fixture_path = 'spec/fixtures'

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
