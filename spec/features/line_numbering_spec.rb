# frozen_string_literal: true

fixture_path = 'spec/fixtures'

describe 'counts csv lines correctly' do
  it 'has correct CVS line numbering' do
    options = {
      col_sep: ",", row_sep: "\n",
      comment_regexp: /^#/, skip_lines: 2, with_line_numbers: true,
    }
    data = SmarterCSV.process("#{fixture_path}/line_numbers.csv", options)

    expect(data.size).to eq 2
    expect(data[0]).to eq({a: 1, b: 2, c: 3, csv_line_number: 6 })
    expect(data[1]).to eq({a: 4, b: 5, c: 6, csv_line_number: 8 })
  end
end
