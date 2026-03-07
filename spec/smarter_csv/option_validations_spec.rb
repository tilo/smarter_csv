# frozen_string_literal: true

fixture_path = 'spec/fixtures'

describe 'option validations' do
  let(:options) { {} }

  it 'loads basic csv file without issues' do
    data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
    expect(data.size).to eq 5
  end

  it 'raises ValidationError for invalid missing_headers value' do
    expect { SmarterCSV.process("#{fixture_path}/basic.csv", missing_headers: :bogus) }
      .to raise_error(SmarterCSV::ValidationError, /invalid missing_headers/)
  end

  it 'raises ValidationError for invalid quote_boundary value' do
    expect { SmarterCSV.process("#{fixture_path}/basic.csv", quote_boundary: :bogus) }
      .to raise_error(SmarterCSV::ValidationError, /invalid quote_boundary/)
  end

  it 'raises ValidationError when quote_char is more than one byte' do
    # The C extension only reads the first byte of quote_char, so a multi-byte
    # quote_char would silently misbehave. Validate early to prevent that.
    expect { SmarterCSV.process("#{fixture_path}/basic.csv", quote_char: "\u00AB") }
      .to raise_error(SmarterCSV::ValidationError, /invalid quote_char.*single byte/)
  end

  it 'raises ValidationError when quote_char is a multi-byte UTF-8 string' do
    expect { SmarterCSV.process("#{fixture_path}/basic.csv", quote_char: "«»") }
      .to raise_error(SmarterCSV::ValidationError, /invalid quote_char.*single byte/)
  end

  [:row_sep, :col_sep, :quote_char].each do |opt|
    [nil, '', :symbol, 1].each do |val|
      context "with #{opt} set to #{val}" do
        let(:option) { opt }
        let(:value) { val }
        let(:options) { { option => value } }

        it "raises an exception if #{opt} is #{val}" do
          expect { SmarterCSV.process("#{fixture_path}/basic.csv", options) }.to raise_exception(SmarterCSV::ValidationError)
        end
      end
    end
  end
end
