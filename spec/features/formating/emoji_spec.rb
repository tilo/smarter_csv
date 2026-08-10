# frozen_string_literal: true

fixture_path = 'spec/fixtures'

[true, false].each do |bool|
  describe "fulfills basic tests with#{bool ? ' C-' : 'out '}acceleration" do
    let(:options) { { acceleration: bool, col_sep: :auto} }

    describe 'basic CSV processing' do
      # works only when testing locally
      unless ENV['CI']
        it 'compiles the acceleration' do
          reader = SmarterCSV::Reader.new('something')
          expect(reader.has_acceleration).to eq true
        end
      end

      it 'loads emoji CSV file' do
        reader = SmarterCSV::Reader.new("#{fixture_path}/emoji.csv", options)
        data = reader.process
        expect(data.size).to eq 3

        data.each do |h|
          h.each_key do |key|
            # all the keys should be symbols
            expect(key.class).to eq Symbol

            expect(%i[first_name last_name purchases score]).to include(key)
          end
          expect(h.size).to be <= 4
        end

        expect(data[0][:score]).to eq '❤️'
        expect(data[1][:score]).to eq '😐'
        expect(data[2][:score]).to eq '😞'
      end
    end
  end
end

# Multi-byte characters adjacent to a literal (mid-field) quote must parse identically on
# both paths. The Ruby parser's byte-level skip-ahead used to hand String#byteindex a
# mid-character byte offset — IndexError — when an unquoted field started with a
# multi-byte character followed by a quote; the C path parsed fine.
describe 'multi-byte characters adjacent to mid-field quotes (both paths)' do
  require 'stringio'

  [true, false].each do |acceleration|
    it "parses a multi-byte char before a literal quote (acceleration: #{acceleration})" do
      result = SmarterCSV.process(StringIO.new("h1,h2\né\"x,y\n"), acceleration: acceleration)
      expect(result).to eq [{ h1: 'é"x', h2: 'y' }]
    end

    it "parses a multi-byte char directly before a lone trailing quote (acceleration: #{acceleration})" do
      result = SmarterCSV.process(StringIO.new("h1,h2\né\",x\n"), acceleration: acceleration)
      expect(result).to eq [{ h1: 'é"', h2: 'x' }]
    end

    it "parses a multi-byte field before a quote during multiline stitching (acceleration: #{acceleration})" do
      data = "h1,h2\n\"a\nb\",é\"c\n"
      result = SmarterCSV.process(StringIO.new(data), acceleration: acceleration)
      expect(result).to eq [{ h1: "a\nb", h2: 'é"c' }]
    end
  end
end
