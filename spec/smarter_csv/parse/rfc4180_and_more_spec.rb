# frozen_string_literal: true

# ------------------------------------------------------------------------------------------
# when testing `parse` methods:
#
# * SmarterCSV.default_options are not loaded when testing `parse` methods by themselves
#
# * make sure to always pass all options to the 'parse' methods, incl. acceleration
#
# * always wrap tests, so that both accelerated and un-accelerated code-paths are run,
#   because the purpose of these tests is to ensure that both accelerated and unaccelerated
#   code paths are behaving identically.
# ------------------------------------------------------------------------------------------

class Klass
  include SmarterCSV::Parser
  def has_acceleration
    !!SmarterCSV::Parser.respond_to?(:parse_csv_line_c)
  end
end

[true, false].each do |bool|
  describe "fulfills RFC-4180 and more with#{bool ? ' C-' : 'out '}acceleration" do
    let(:options) { {col_sep: ',', row_sep: $INPUT_RECORD_SEPARATOR, quote_char: '"', acceleration: bool } }
    let(:instance) { Klass.new }

    context 'parses simple CSV' do
      context 'RFC-4180' do
        it 'separating on col_sep' do
          line = 'aaa,bbb,ccc'
          expect(instance.send(:parse, line, options)).to eq [%w[aaa bbb ccc], 3]
        end

        it 'preserves whitespace' do
          line = ' aaa , bbb , ccc '
          expect(instance.send(:parse, line, options)).to eq [
            [' aaa ', ' bbb ', ' ccc '], 3
          ]
        end
      end

      context 'extending RFC-4180' do
        it 'with extra col_sep' do
          line = 'aaa,bbb,ccc,'
          expect(instance.send(:parse, line, options)).to eq [
            ['aaa', 'bbb', 'ccc', ''], 4
          ]
        end

        it 'with extra col_sep with given header_size' do
          line = 'aaa,bbb,ccc,'
          expect(instance.send(:parse, line, options, 3)).to eq [
            %w[aaa bbb ccc], 3
          ]
        end

        it 'with multiple extra col_sep' do
          line = 'aaa,bbb,ccc,,,'
          expect(instance.send(:parse, line, options)).to eq [
            ['aaa', 'bbb', 'ccc', '', '', ''], 6
          ]
        end

        it 'with multiple extra col_sep' do
          line = 'aaa,bbb,ccc,,,'
          expect(instance.send(:parse, line, options, 3)).to eq [
            %w[aaa bbb ccc], 3
          ]
        end

        it 'with multiple complex col_sep' do
          line = 'aaa<=>bbb<=>ccc<=><=><=>'
          expect(instance.send(:parse, line, options.merge({col_sep: '<=>'}))).to eq [
            ['aaa', 'bbb', 'ccc', '', '', ''], 6
          ]
        end

        it 'with multiple complex col_sep with given header_size' do
          line = 'aaa<=>bbb<=>ccc<=><=><=>'
          expect(instance.send(:parse, line, options.merge({col_sep: '<=>'}), 3)).to eq [
            %w[aaa bbb ccc], 3
          ]
        end
      end
    end

    context 'parses quoted CSV' do
      context 'RFC-4180' do
        it 'separating on col_sep' do
          line = '"aaa","bbb","ccc"'
          expect(instance.send(:parse, line, options)).to eq [%w[aaa bbb ccc], 3]
        end

        it 'parses corner case correctly' do
          line = '"Board 4""","$17.40","10000003427"'
          expect(instance.send(:parse, line, options)).to eq [
            ['Board 4"', '$17.40', '10000003427'], 3
          ]
        end

        it 'quoted parts can contain spaces' do
          line = '" aaa1 aaa2 "," bbb1 bbb2 "," ccc1 ccc2 "'
          expect(instance.send(:parse, line, options)).to eq [
            [' aaa1 aaa2 ', ' bbb1 bbb2 ', ' ccc1 ccc2 '], 3
          ]
        end

        it 'quoted parts can contain row_sep' do
          line = '"aaa1, aaa2","bbb1, bbb2","ccc1, ccc2"'
          expect(instance.send(:parse, line, options)).to eq [
            ['aaa1, aaa2', 'bbb1, bbb2', 'ccc1, ccc2'], 3
          ]
        end

        it 'quoted parts can contain row_sep' do
          line = '"aaa1, ""aaa2"", aaa3","""bbb1"", bbb2","ccc1, ""ccc2"""'
          expect(instance.send(:parse, line, options)).to eq [
            ['aaa1, "aaa2", aaa3', '"bbb1", bbb2', 'ccc1, "ccc2"'], 3
          ]
        end

        it 'some fields are quoted' do
          line = '1,"board 4""",12.95'
          expect(instance.send(:parse, line, options)).to eq [
            ['1', 'board 4"', '12.95'], 3
          ]
        end

        it 'separating on col_sep' do
          line = '"some","thing","""completely"" different"'
          expect(instance.send(:parse, line, options)).to eq [
            ['some', 'thing', '"completely" different'], 3
          ]
        end
      end

      context 'extending RFC-4180' do
        it 'with extra col_sep, without given header_size' do
          line = '"aaa","bbb","ccc",'
          expect(instance.send(:parse, line, options)).to eq [
            ['aaa', 'bbb', 'ccc', ''], 4
          ]
        end

        it 'with extra col_sep, with given header_size' do
          line = '"aaa","bbb","ccc",'
          expect(instance.send(:parse, line, options, 3)).to eq [%w[aaa bbb ccc], 3]
        end

        it 'with multiple extra col_sep, without given header_size' do
          line = '"aaa","bbb","ccc",,,'
          expect(instance.send(:parse, line, options)).to eq [
            ['aaa', 'bbb', 'ccc', '', '', ''], 6
          ]
        end

        it 'with multiple extra col_sep, with given header_size' do
          line = '"aaa","bbb","ccc",,,'
          expect(instance.send(:parse, line, options, 3)).to eq [
            %w[aaa bbb ccc], 3
          ]
        end

        it 'with multiple complex extra col_sep, without given header_size' do
          line = '"aaa"<=>"bbb"<=>"ccc"<=><=><=>'
          expect(instance.send(:parse, line, options.merge({col_sep: '<=>'}))).to eq [
            ['aaa', 'bbb', 'ccc', '', '', ''], 6
          ]
        end

        it 'with multiple complex extra col_sep, with given header_size' do
          line = '"aaa"<=>"bbb"<=>"ccc"<=><=><=>'
          expect(instance.send(:parse, line, options.merge({col_sep: '<=>'}), 3)).to eq [
            %w[aaa bbb ccc], 3
          ]
        end
      end
    end

    # relaxed parsing compared to RFC-4180
    context 'liberal_parsing' do
      it 'parses corner case correctly' do
        line = 'is,this "three, or four",fields'
        expect(instance.send(:parse, line, options)).to eq [
          ['is', 'this "three, or four"', 'fields'], 3
        ]
      end
    end
  end # bool
end
