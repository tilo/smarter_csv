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
end
