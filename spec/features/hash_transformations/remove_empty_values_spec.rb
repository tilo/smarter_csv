# frozen_string_literal: true

require 'stringio'

fixture_path = 'spec/fixtures'

describe ':remove_empty_values option' do
  [true, false].each do |acceleration|
    context "acceleration: #{acceleration}" do
      it 'removes empty values' do
        options = {row_sep: :auto, remove_empty_values: true, acceleration: acceleration}
        data = SmarterCSV.process("#{fixture_path}/empty.csv", options)
        expect(data.size).to eq 1
        expect(data[0].keys).to eq(%i[not_empty_1 not_empty_2 not_empty_3])
      end
    end
  end
end

# A field that is entirely whitespace counts as "empty" — and "whitespace" should mean the same
# thing as Ruby's [[:space:]] / Rails' String#blank? (the full Unicode White_Space set), not just
# ASCII. The :a column carries the candidate value; :b / :c keep the row non-empty.
describe ':remove_empty_values and Unicode whitespace' do
  {
    " " => 'NBSP (U+00A0)',
    "　" => 'ideographic space (U+3000)',
    " " => 'em space (U+2003)',
    " " => 'line separator (U+2028)',
    " " => 'medium mathematical space (U+205F)',
    " " => 'Ogham space mark (U+1680)',
    " \t 　" => 'mixed Unicode + ASCII whitespace',
  }.each do |blank_value, label|
    [true, false].each do |accel|
      it "treats a field of #{label} as blank (acceleration: #{accel})" do
        io = StringIO.new("a,b,c\n#{blank_value},keep,1\n")
        data = SmarterCSV.process(io, remove_empty_values: true, col_sep: ',', acceleration: accel)
        expect(data).to eq [{ b: 'keep', c: 1 }]
      end
    end
  end

  # Not Unicode whitespace (zero-width format chars) — must be kept.
  {
    "​" => 'zero-width space (U+200B)',
    "﻿" => 'ZERO WIDTH NO-BREAK SPACE / BOM (U+FEFF)',
    " x" => 'NBSP followed by a letter',
  }.each do |kept_value, label|
    [true, false].each do |accel|
      it "keeps a field of #{label} (acceleration: #{accel})" do
        io = StringIO.new("a,b,c\n#{kept_value},keep,1\n")
        data = SmarterCSV.process(io, remove_empty_values: true, col_sep: ',', acceleration: accel)
        expect(data.first).to have_key(:a)
      end
    end
  end
end
