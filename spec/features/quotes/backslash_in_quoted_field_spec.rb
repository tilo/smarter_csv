# frozen_string_literal: true

# Regression test for GitHub issue #316
# https://github.com/tilo/smarter_csv/issues/316
#
# When a quoted field ends with a backslash (e.g. "X,Y\"), the parser
# incorrectly treats \" as an escaped quote and raises MalformedCSV.
# Per RFC 4180, backslash has no special meaning in CSV — only doubled
# quote characters ("") serve as escapes.

[true, false].each do |bool|
  describe "backslash as last char in quoted field with#{bool ? ' C-' : 'out '}acceleration" do
    let(:options) { { acceleration: bool } }

    # Exact reproducer from issue #316
    context 'quoted field ending with a backslash' do
      let(:csv) { "Col A,Col B\n\"X,Y\\\",Y" }

      it 'parses successfully without raising MalformedCSV' do
        result = SmarterCSV.process(StringIO.new(csv), **options)
        expect(result.size).to eq 1
        expect(result[0][:"col_a"]).to eq "X,Y\\"
        expect(result[0][:"col_b"]).to eq "Y"
      end
    end

    # Contrast case from issue #316 — characters after backslash work fine
    context 'quoted field with backslash followed by other characters' do
      let(:csv) { "Col A,Col B\n\"X,Y\\ok\",Y" }

      it 'parses successfully' do
        result = SmarterCSV.process(StringIO.new(csv), **options)
        expect(result.size).to eq 1
        expect(result[0][:"col_a"]).to eq "X,Y\\ok"
        expect(result[0][:"col_b"]).to eq "Y"
      end
    end

    # Additional edge cases around backslashes in quoted fields
    context 'quoted field containing only a backslash' do
      let(:csv) { "Col A,Col B\n\"\\\",Y" }

      it 'parses successfully' do
        result = SmarterCSV.process(StringIO.new(csv), **options)
        expect(result.size).to eq 1
        expect(result[0][:"col_a"]).to eq "\\"
        expect(result[0][:"col_b"]).to eq "Y"
      end
    end

    context 'quoted field ending with double backslash' do
      let(:csv) { "Col A,Col B\n\"X,Y\\\\\",Z" }

      it 'parses successfully' do
        result = SmarterCSV.process(StringIO.new(csv), **options)
        expect(result.size).to eq 1
        expect(result[0][:"col_a"]).to eq "X,Y\\\\"
        expect(result[0][:"col_b"]).to eq "Z"
      end
    end

    context 'multiple rows with backslash at end of quoted field' do
      let(:csv) { "Col A,Col B\n\"path\\to\\\",val1\n\"another\\\",val2" }

      it 'parses all rows successfully' do
        result = SmarterCSV.process(StringIO.new(csv), **options)
        expect(result.size).to eq 2
        expect(result[0][:"col_a"]).to eq "path\\to\\"
        expect(result[0][:"col_b"]).to eq "val1"
        expect(result[1][:"col_a"]).to eq "another\\"
        expect(result[1][:"col_b"]).to eq "val2"
      end
    end
  end
end
