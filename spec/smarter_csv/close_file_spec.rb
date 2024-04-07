# frozen_string_literal: true

fixture_path = 'spec/fixtures'

describe 'file operations' do
  it 'close file after using it' do
    options = {col_sep: "\cA", row_sep: "\cB", comment_regexp: /^#/, strings_as_keys: true}

    file = File.new("#{fixture_path}/binary.csv")

    SmarterCSV.process(file, options)

    expect(file.closed?).to eq true
  end
end
