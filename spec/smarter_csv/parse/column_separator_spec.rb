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

[true, false].each do |bool|
  describe "fulfills RFC-4180 and more with#{bool ? ' C-' : 'out '}acceleration" do
    describe 'parse with col_sep' do
      let(:options) { {quote_char: '"', acceleration: bool} }

      it 'parses with comma' do
        line = "a,b,,d"
        options.merge!({col_sep: ","})
        array, array_size = SmarterCSV.send(:parse, line, options)
        expect(array).to eq ['a', 'b', '', 'd']
        expect(array_size).to eq 4
      end

      it 'parses trailing commas' do
        line = "a,b,c,,"
        options.merge!({col_sep: ","})
        array, array_size = SmarterCSV.send(:parse, line, options)
        expect(array).to eq ['a', 'b', 'c', '', '']
        expect(array_size).to eq 5
      end

      it 'parses with space' do
        line = "a b  d"
        options.merge!({col_sep: " "})
        array, array_size = SmarterCSV.send(:parse, line, options)
        expect(array).to eq ['a', 'b', '', 'd']
        expect(array_size).to eq 4
      end

      it 'parses with tab' do
        line = "a\tb\t\td"
        options.merge!({col_sep: "\t"})
        array, array_size = SmarterCSV.send(:parse, line, options)
        expect(array).to eq ['a', 'b', '', 'd']
        expect(array_size).to eq 4
      end

      it 'parses with multiple space separator' do
        line = "a b    d"
        options.merge!({col_sep: "  "})
        array, array_size = SmarterCSV.send(:parse, line, options)
        expect(array).to eq ['a b', '', 'd']
        expect(array_size).to eq 3
      end

      it 'parses with multiple char separator' do
        line = '<=><=>A<=>B<=>C'
        options.merge!({col_sep: "<=>"})
        array, array_size = SmarterCSV.send(:parse, line, options)
        expect(array).to eq ["", "", "A", "B", "C"]
        expect(array_size).to eq 5
      end

      it 'parses trailing multiple char separator' do
        line = '<=><=>A<=>B<=>C<=><=>'
        options.merge!({col_sep: "<=>"})
        array, array_size = SmarterCSV.send(:parse, line, options)
        expect(array).to eq ["", "", "A", "B", "C", "", ""]
        expect(array_size).to eq 7
      end
    end
  end
end
