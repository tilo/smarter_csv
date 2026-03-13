# frozen_string_literal: true

# Tests for strip_whitespace behavior, especially the difference from Ruby CSV.
#
# Ruby CSV `strip: true` preserves whitespace inside quoted fields:
#   CSV.parse_line('"  a  ","  b  "', strip: true) => ["  a  ", "  b  "]
#
# SmarterCSV `strip_whitespace: true` (the default) strips ALL fields,
# including quoted ones:
#   SmarterCSV.process(io) => [{ col: "a" }]   # whitespace stripped
#
# This is intentional — SmarterCSV's primary use case is importing structured
# data where leading/trailing whitespace is almost always noise.
# Users who need to preserve inner whitespace should pass strip_whitespace: false.

[true, false].each do |bool|
  describe "strip_whitespace option with#{bool ? ' C-' : 'out '}acceleration" do
    let(:base_options) { { acceleration: bool } }

    # ----------------------------------------------------------------
    # Unquoted fields — baseline, no controversy
    # ----------------------------------------------------------------
    describe 'unquoted fields' do
      it 'strips leading and trailing whitespace by default (strip_whitespace: true)' do
        csv = "a,b\n  hello  ,  world  \n"
        data = SmarterCSV.process(StringIO.new(csv), base_options)
        expect(data[0][:a]).to eq 'hello'
        expect(data[0][:b]).to eq 'world'
      end

      it 'preserves whitespace when strip_whitespace: false' do
        csv = "a,b\n  hello  ,  world  \n"
        data = SmarterCSV.process(StringIO.new(csv), base_options.merge(strip_whitespace: false))
        expect(data[0][:a]).to eq '  hello  '
        expect(data[0][:b]).to eq '  world  '
      end
    end

    # ----------------------------------------------------------------
    # Quoted fields — SmarterCSV strips; Ruby CSV does NOT
    # ----------------------------------------------------------------
    describe 'quoted fields' do
      # SmarterCSV differs from Ruby CSV here:
      # Ruby CSV strip: true preserves content of quoted fields.
      # SmarterCSV strip_whitespace: true strips even quoted field content.
      it 'strips whitespace inside quoted fields by default (strip_whitespace: true)' do
        csv = "name\n\"  Alice  \"\n"
        data = SmarterCSV.process(StringIO.new(csv), base_options)
        expect(data[0][:name]).to eq 'Alice'
      end

      it 'preserves whitespace inside quoted fields when strip_whitespace: false' do
        csv = "name\n\"  Alice  \"\n"
        data = SmarterCSV.process(StringIO.new(csv), base_options.merge(strip_whitespace: false))
        expect(data[0][:name]).to eq '  Alice  '
      end

      it 'strips both quoted and unquoted fields in the same row' do
        csv = "a,b\n\"  hello  \",  world  \n"
        data = SmarterCSV.process(StringIO.new(csv), base_options)
        expect(data[0][:a]).to eq 'hello'
        expect(data[0][:b]).to eq 'world'
      end

      it 'preserves both quoted and unquoted fields when strip_whitespace: false' do
        csv = "a,b\n\"  hello  \",  world  \n"
        data = SmarterCSV.process(StringIO.new(csv), base_options.merge(strip_whitespace: false))
        expect(data[0][:a]).to eq '  hello  '
        expect(data[0][:b]).to eq '  world  '
      end

      it 'strips whitespace from a quoted field that embeds the separator' do
        # Field value is "  hello, world  " — the comma is inside the quoted field
        csv = "col\n\"  hello, world  \"\n"
        data = SmarterCSV.process(StringIO.new(csv), base_options)
        expect(data[0][:col]).to eq 'hello, world'
      end

      it 'preserves embedded-separator field whitespace when strip_whitespace: false' do
        csv = "col\n\"  hello, world  \"\n"
        data = SmarterCSV.process(StringIO.new(csv), base_options.merge(strip_whitespace: false))
        expect(data[0][:col]).to eq '  hello, world  '
      end
    end

    # ----------------------------------------------------------------
    # strip_whitespace does not affect empty fields
    # ----------------------------------------------------------------
    describe 'empty fields' do
      it 'an all-whitespace unquoted field becomes empty (removed by default remove_empty_values)' do
        csv = "a,b\n   ,val\n"
        data = SmarterCSV.process(StringIO.new(csv), base_options)
        # stripped to '' → removed by remove_empty_values: true
        expect(data[0]).not_to have_key(:a)
        expect(data[0][:b]).to eq 'val'
      end

      it 'an all-whitespace unquoted field kept as empty string with remove_empty_values: false' do
        csv = "a,b\n   ,val\n"
        data = SmarterCSV.process(StringIO.new(csv), base_options.merge(remove_empty_values: false))
        expect(data[0][:a]).to eq ''
        expect(data[0][:b]).to eq 'val'
      end
    end
  end
end
