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

# Design decision: all empty field values are ONE shared, frozen, UTF-8 empty-string
# object per path (no per-empty-field object retained in the results; mutating an empty
# value raises FrozenError instead of silently changing the other empty values).
# Relevant with remove_empty_values: false — with the default true, empties are dropped.
describe 'shared frozen empty string for empty values' do
  [true, false].each do |acceleration|
    it "is one frozen UTF-8 object for all empty values (acceleration: #{acceleration})" do
      io = StringIO.new("a,b,c\n,,x\n,,y\n")
      data = SmarterCSV.process(io, remove_empty_values: false, acceleration: acceleration)
      empties = data.flat_map { |h| h.values.select { |v| v == '' } }
      expect(empties.size).to eq 4
      expect(empties).to all(be_frozen)
      expect(empties.map(&:object_id).uniq.size).to eq 1
      expect(empties.first.encoding).to eq Encoding::UTF_8
    end

    it "also shares the object for quoted and whitespace-only fields (acceleration: #{acceleration})" do
      io = StringIO.new(%{a,b,c\n"", ,x\n})
      data = SmarterCSV.process(io, remove_empty_values: false, acceleration: acceleration)
      empties = data.first.values.select { |v| v == '' }
      expect(empties.size).to eq 2
      expect(empties).to all(be_frozen)
      expect(empties.map(&:object_id).uniq.size).to eq 1
    end
  end
end
