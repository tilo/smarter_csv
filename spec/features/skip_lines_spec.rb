# frozen_string_literal: true

fixture_path = 'spec/fixtures'

describe ':skip_lines option' do
  it 'loads_csv_file_skipping_lines' do
    options = {skip_lines: 3}
    data = SmarterCSV.process("#{fixture_path}/skip_lines.csv", options)
    expect(data.size).to eq 4

    data.each do |item|
      item.each_key do |key|
        expect(%i[first_name last_name dogs cats birds fish]).to include(key)
      end
    end
  end

  it 'loads_csv_with_user_defined_headers' do
    options = {skip_lines: 3, headers_in_file: true, user_provided_headers: %i[a b c d e f]}
    data = SmarterCSV.process("#{fixture_path}/skip_lines.csv", options)
    expect(data.size).to eq 4

    data.each do |item|
      item.each_key do |key|
        expect(%i[a b c d e f]).to include(key)
      end
    end
  end
end
