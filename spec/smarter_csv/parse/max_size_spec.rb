# frozen_string_literal: true

require 'spec_helper'

# the purpose of the max_size parameter is to handle a corner case where
# CSV lines contain more fields than the header.
# In which case the remaining fields in the line are ignored

[true, false].each do |bool|
  describe "fulfills RFC-4180 and more with#{bool ? ' C-' : 'out '}acceleration" do
    let(:options) { {acceleration: bool} }

    describe 'splitting line up to max_size' do
      before do
        options.merge!({quote_char: '"', col_sep: ","})
      end

      context 'without quotes' do
        it 'without max_size' do
          line = '1,2,3,4,5,6'
          array, _array_size = SmarterCSV.send(:parse, line, options)
          expect(array).to eq %w[1 2 3 4 5 6]
        end

        it 'with max_size = 7' do
          line = '1,2,3,4,5,6'
          array, _array_size = SmarterCSV.send(:parse, line, options, 7)
          expect(array).to eq %w[1 2 3 4 5 6]
        end

        it 'with max_size = 6' do
          line = '1,2,3,4,5,6'
          array, _array_size = SmarterCSV.send(:parse, line, options, 6)
          expect(array).to eq %w[1 2 3 4 5 6]
        end

        it 'with max_size = 5' do
          line = '1,2,3,4,5,6'
          array, _array_size = SmarterCSV.send(:parse, line, options, 5)
          expect(array).to eq %w[1 2 3 4 5]
        end

        it 'with max_size = 4' do
          line = '1,2,3,4,5,6'
          array, _array_size = SmarterCSV.send(:parse, line, options, 4)
          expect(array).to eq %w[1 2 3 4]
        end

        it 'with max_size = 3' do
          line = '1,2,3,4,5,6'
          array, _array_size = SmarterCSV.send(:parse, line, options, 3)
          expect(array).to eq %w[1 2 3]
        end

        it 'with max_size = 2' do
          line = '1,2,3,4,5,6'
          array, _array_size = SmarterCSV.send(:parse, line, options, 2)
          expect(array).to eq %w[1 2]
        end

        it 'with max_size = 1' do
          line = '1,2,3,4,5,6'
          array, _array_size = SmarterCSV.send(:parse, line, options, 1)
          expect(array).to eq ['1']
        end

        it 'with max_size = 0' do
          line = '1,2,3,4,5,6'
          array, _array_size = SmarterCSV.send(:parse, line, options, 0)
          expect(array).to eq []
        end

        it 'with max_size = -1' do
          line = '1,2,3,4,5,6'
          array, _array_size = SmarterCSV.send(:parse, line, options, -1)
          expect(array).to eq []
        end
      end

      context 'with quotes' do
        it 'without max_size' do
          line = '"1","2","3","4","5","6"'
          array, _array_size = SmarterCSV.send(:parse, line, options)
          expect(array).to eq %w[1 2 3 4 5 6]
        end

        it 'with max_size = 7' do
          line = '"1","2","3","4","5","6"'
          array, _array_size = SmarterCSV.send(:parse, line, options, 7)
          expect(array).to eq %w[1 2 3 4 5 6]
        end

        it 'with max_size = 6' do
          line = '"1","2","3","4","5","6"'
          array, _array_size = SmarterCSV.send(:parse, line, options, 6)
          expect(array).to eq %w[1 2 3 4 5 6]
        end

        it 'with max_size = 5' do
          line = '"1","2","3","4","5","6"'
          array, _array_size = SmarterCSV.send(:parse, line, options, 5)
          expect(array).to eq %w[1 2 3 4 5]
        end

        it 'with max_size = 4' do
          line = '"1","2","3","4","5","6"'
          array, _array_size = SmarterCSV.send(:parse, line, options, 4)
          expect(array).to eq %w[1 2 3 4]
        end

        it 'with max_size = 3' do
          line = '"1","2","3","4","5","6"'
          array, _array_size = SmarterCSV.send(:parse, line, options, 3)
          expect(array).to eq %w[1 2 3]
        end

        it 'with max_size = 2' do
          line = '"1","2","3","4","5","6"'
          array, _array_size = SmarterCSV.send(:parse, line, options, 2)
          expect(array).to eq %w[1 2]
        end

        it 'with max_size = 1' do
          line = '"1","2","3","4","5","6"'
          array, _array_size = SmarterCSV.send(:parse, line, options, 1)
          expect(array).to eq ['1']
        end

        it 'with max_size = 0' do
          line = '"1","2","3","4","5","6"'
          array, _array_size = SmarterCSV.send(:parse, line, options, 0)
          expect(array).to eq []
        end

        it 'with max_size = -1' do
          line = '"1","2","3","4","5","6"'
          array, _array_size = SmarterCSV.send(:parse, line, options, -1)
          expect(array).to eq []
        end
      end
    end
  end # bool
end
