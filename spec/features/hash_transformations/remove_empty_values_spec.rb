# frozen_string_literal: true

require 'stringio'

fixture_path = 'spec/fixtures'

[true, false].each do |acceleration|
  describe ':remove_empty_values option' do
    context "acceleration: #{acceleration}" do
      it 'removes empty values' do
        options = {row_sep: :auto, remove_empty_values: true, acceleration: acceleration}
        data = SmarterCSV.process("#{fixture_path}/empty.csv", options)
        expect(data.size).to eq 1
        expect(data[0].keys).to eq(%i[not_empty_1 not_empty_2 not_empty_3])
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
      " " => 'en quad (U+2000) — low edge of the E2 80 8x whitespace range',
      " " => 'hair space (U+200A) — high edge of that range (U+200B right after is NOT whitespace)',
      " \t 　" => 'mixed Unicode + ASCII whitespace',
    }.each do |blank_value, label|
      it "treats a field of #{label} as blank (acceleration: #{acceleration})" do
        io = StringIO.new("a,b,c\n#{blank_value},keep,1\n")
        data = SmarterCSV.process(io, remove_empty_values: true, col_sep: ',', acceleration: acceleration)
        expect(data).to eq [{ b: 'keep', c: 1 }]
      end
    end

    # Not Unicode whitespace (zero-width format chars) — must be kept.
    {
      "​" => 'zero-width space (U+200B)',
      "﻿" => 'ZERO WIDTH NO-BREAK SPACE / BOM (U+FEFF)',
      " x" => 'NBSP followed by a letter',
    }.each do |kept_value, label|
      it "keeps a field of #{label} (acceleration: #{acceleration})" do
        io = StringIO.new("a,b,c\n#{kept_value},keep,1\n")
        data = SmarterCSV.process(io, remove_empty_values: true, col_sep: ',', acceleration: acceleration)
        expect(data.first).to have_key(:a)
      end
    end
  end
end

# Design decision: the C path returns ONE shared empty-string object for all empty values
# (avoids a String allocation per empty field). That shared object must be FROZEN — an
# unfrozen shared object meant mutating one empty value silently changed every other empty
# value in the result — and UTF-8, like Ruby's empty strings.
# (C path only for now: whether the Ruby path should substitute the shared object for the
# fresh strings String#split produces is a pending design decision.)
describe 'shared empty string on the C path' do
  it 'is one frozen UTF-8 object for all empty values' do
    io = StringIO.new("a,b,c\n,,x\n,,y\n")
    data = SmarterCSV.process(io, remove_empty_values: false, acceleration: true)
    empties = data.flat_map { |h| h.values.select { |v| v == '' } }
    expect(empties.size).to eq 4
    expect(empties).to all(be_frozen)
    expect(empties.map(&:object_id).uniq.size).to eq 1
    expect(empties.first.encoding).to eq Encoding::UTF_8
  end
end
