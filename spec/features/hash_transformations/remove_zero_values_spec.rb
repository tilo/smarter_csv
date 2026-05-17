# frozen_string_literal: true

require 'stringio'

fixture_path = 'spec/fixtures'

[true, false].each do |accel|
  describe ":remove_zero_values option with#{accel ? ' C-' : 'out '}acceleration" do
    let(:options) { { remove_zero_values: true, remove_empty_values: true, acceleration: accel } }

    it 'removes zero values' do
      data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
      expect(data.size).to eq 5

      data.each do |hash|
        hash.each_key do |key|
          expect(key.class).to eq Symbol # all the keys should be symbols

          expect(%i[first_name last_name dogs cats birds fish]).to include(key)
        end

        expect(hash.values).not_to include(0)

        expect(hash.size).to be <= 6
      end
    end

    it 'keeps zero values when remove_zero_values is false' do
      data = SmarterCSV.process("#{fixture_path}/basic.csv", remove_zero_values: false, remove_empty_values: true, acceleration: accel)

      expect(data.size).to eq 5
      expect(data.any? { |hash| hash.values.include?(0) }).to eq true

      miles = data.find { |hash| hash[:first_name] == 'Miles' }
      expect(miles).to include(dogs: 0, cats: 0, birds: 0, fish: 21)
    end

    # ZERO_REGEX = /\A[+-]?0+(?:\.0+)?\z/ — every textual form of zero, signed or not.
    # The :a column carries the candidate value; :b / :c keep the row non-empty.
    describe 'textual zero forms' do
      let(:options) { { remove_zero_values: true, remove_empty_values: true, col_sep: ',', acceleration: accel } }

      %w[0 00 000 0.0 0.00 00.00 +0 +0.0 +0.00 -0 -0.0 -0.00].each do |zero_string|
        it "removes a field equal to #{zero_string.inspect}" do
          io = StringIO.new("a,b,c\n#{zero_string},keep,1\n")
          data = SmarterCSV.process(io, options)
          expect(data).to eq [{ b: 'keep', c: 1 }]
        end
      end

      # Not zeros — must survive (and not be coerced to 0)
      %w[0.5 -0.5 +0.1 0.05 0.001 10 100 -1].each do |non_zero_string|
        it "keeps a field equal to #{non_zero_string.inspect}" do
          io = StringIO.new("a,b,c\n#{non_zero_string},keep,1\n")
          data = SmarterCSV.process(io, options)
          expect(data.first).to have_key(:a)
          expect(data.first[:a]).not_to eq 0
        end
      end
    end
  end
end
