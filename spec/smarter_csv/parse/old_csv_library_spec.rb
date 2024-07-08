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
    true
  end
end

[true, false].each do |bool|
  describe "fulfills RFC-4180 and more with#{bool ? ' C-' : 'out '}acceleration" do
    let(:instance) { Klass.new }

    describe 'old CSV library parsing tests' do
      let(:options) { {quote_char: '"', col_sep: ",", acceleration: bool} }

      [["\t", ["\t"]],
       ["foo,\"\"\"\"\"\",baz", ["foo", "\"\"", "baz"]],
       ["foo,\"\"\"bar\"\"\",baz", ["foo", "\"bar\"", "baz"]],
       ["\"\"\"\n\",\"\"\"\n\"", ["\"\n", "\"\n"]],
       ["foo,\"\r\n\",baz", ["foo", "\r\n", "baz"]],
       ["\"\"", [""]],
       ["foo,\"\"\"\",baz", ["foo", "\"", "baz"]],
       ["foo,\"\r.\n\",baz", ["foo", "\r.\n", "baz"]],
       ["foo,\"\r\",baz", ["foo", "\r", "baz"]],
       ["foo,\"\",baz", ["foo", "", "baz"]],
       ["\",\"", [","]],
       ["foo", ["foo"]],
       [",,", ['', '', '']],
       [",", ['', '']],
       ["foo,\"\n\",baz", %W[foo \n baz]],
       ["foo,,baz", ["foo", '', "baz"]],
       ["\"\"\"\r\",\"\"\"\r\"", ["\"\r", "\"\r"]],
       ["\",\",\",\"", [",", ","]],
       ["foo,bar,", ["foo", "bar", '']],
       [",foo,bar", ['', "foo", "bar"]],
       ["foo,bar", %w[foo bar]],
       [";", [";"]],
       ["\t,\t", %W[\t \t]],
       ["foo,\"\r\n\r\",baz", ["foo", "\r\n\r", "baz"]],
       ["foo,\"\r\n\n\",baz", ["foo", "\r\n\n", "baz"]],
       ["foo,\"foo,bar\",baz", ["foo", "foo,bar", "baz"]],
       [";,;", [";", ";"]]].each do |line, result|
        it "parses #{line} as #{result.inspect}" do
          array, _array_size = instance.send(:parse, line, options)
          expect(array).to eq result
        end
      end

      [["foo,\"\"\"\"\"\",baz", ["foo", "\"\"", "baz"]],
       ["foo,\"\"\"bar\"\"\",baz", ["foo", "\"bar\"", "baz"]],
       ["foo,\"\r\n\",baz", ["foo", "\r\n", "baz"]],
       ["\"\"", [""]],
       ["foo,\"\"\"\",baz", ["foo", "\"", "baz"]],
       ["foo,\"\r.\n\",baz", ["foo", "\r.\n", "baz"]],
       ["foo,\"\r\",baz", ["foo", "\r", "baz"]],
       ["foo,\"\",baz", ["foo", "", "baz"]],
       ["foo", ["foo"]],
       [",,", ['', '', '']],
       [",", ['', '']],
       ["foo,\"\n\",baz", %W[foo \n baz]],
       ["foo,,baz", ["foo", '', "baz"]],
       ["foo,bar", %w[foo bar]],
       ["foo,\"\r\n\n\",baz", ["foo", "\r\n\n", "baz"]],
       ["foo,\"foo,bar\",baz", ["foo", "foo,bar", "baz"]]].each do |line, result|
        it "parses #{line} as #{result.inspect}" do
          array, _array_size = instance.send(:parse, line, options)
          expect(array).to eq result
        end
      end

      it 'quoted test' do
        line = '"This",is,2"","3""",test'
        array, _array_size = instance.send(:parse, line, options)
        expect(array).to eq ["This", "is", '2"', '3"', "test"]
      end

      it 'mixed quotes' do
        line = %{Ten Thousand,10000, 2710 ,,"10,000","It's ""10 Grand"", baby",10K}
        array, _array_size = instance.send(:parse, line, options)
        expect(array).to eq ["Ten Thousand", "10000", " 2710 ", "", "10,000", "It's \"10 Grand\", baby", "10K"]
      end

      it 'single quotes in fields' do
        line = 'Indoor Chrome,49.2"" L x 49.2"" W x 20.5"" H,Chrome,"Crystal,Metal,Wood",23.12'
        array, _array_size = instance.send(:parse, line, options)
        expect(array).to eq ['Indoor Chrome', '49.2" L x 49.2" W x 20.5" H', 'Chrome', 'Crystal,Metal,Wood', '23.12']
      end
    end
  end
end
