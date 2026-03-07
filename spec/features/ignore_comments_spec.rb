# frozen_string_literal: true

fixture_path = 'spec/fixtures'

describe ':comment_regexp option' do
  it 'by default does not ignore comments in CSV files' do
    options = {}
    data = SmarterCSV.process("#{fixture_path}/ignore_comments.csv", options)

    expect(data.size).to eq 8

    data.each do |h|
      h.each_key do |key|
        expect(key.is_a?(Symbol)).to be_truthy # all the keys should be symbols

        expect(%i[not_a_comment#first_name last_name dogs cats birds fish]).to include(key)
      end
    end
  end

  it 'ignore comments in CSV files using comment_regexp' do
    options = {comment_regexp: /\A#/}
    data = SmarterCSV.process("#{fixture_path}/ignore_comments.csv", options)

    expect(data.size).to eq 5

    data.each do |h|
      h.each_key do |key|
        expect(key.is_a?(Symbol)).to be_truthy # all the keys should be symbols

        expect(%i[not_a_comment#first_name last_name dogs cats birds fish]).to include(key)
      end
    end
  end

  it 'ignore comments in CSV files with CRLF' do
    options = {row_sep: "\r\n"}
    data = SmarterCSV.process("#{fixture_path}/ignore_comments2.csv", options)

    # all the keys should be symbols
    expect(data.size).to eq 1
    expect(data.first[:h1]).to eq 'a'
    expect(data.first[:h2]).to eq "b\r\n#c"
  end

  # comment_regexp is matched against the raw physical line.
  # A quoted field whose VALUE starts with '#' must NOT be skipped — the raw
  # line starts with '"', not '#', so the regex does not match.
  # (Mirrors Ruby CSV test_regexp_quoted from test/csv/parse/test_skip_lines.rb)
  it 'does not skip a row whose quoted field value starts with #' do
    csv = "category,value\n\"#sales\",100\n"
    data = SmarterCSV.process(StringIO.new(csv), comment_regexp: /\A#/)
    expect(data.size).to eq 1
    expect(data[0][:category]).to eq '#sales'
    expect(data[0][:value]).to eq 100
  end

  it 'skips an unquoted line starting with # but not a quoted one in the same file' do
    csv = "category,value\n#this is a comment\n\"#sales\",100\n"
    data = SmarterCSV.process(StringIO.new(csv), comment_regexp: /\A#/)
    expect(data.size).to eq 1
    expect(data[0][:category]).to eq '#sales'
  end
end
