# frozen_string_literal: true

fixture_path = 'spec/fixtures'

describe ':strings_as_keys option' do
  [true, false].each do |acceleration|
    it "uses strings as hash keys (acceleration: #{acceleration})" do
      options = {strings_as_keys: true, acceleration: acceleration}
      data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
      expect(data.size).to eq 5

      data.each do |hash|
        hash.each_key do |key|
          expect(key.class).to eq String # all the keys should be symbols

          expect(%w[first_name last_name dogs cats birds fish]).to include(key)
        end

        expect(hash.size).to be <= 6
      end
    end
  end

  # An empty-string header key (possible with strings_as_keys: true and duplicate_header_suffix:
  # nil, which disables the column_N auto-naming) is dropped from the row hash — on both paths.
  describe 'empty-string header key (both paths)' do
    require 'stringio'

    [true, false].each do |acceleration|
      it "drops the '' key from the row hash (acceleration: #{acceleration})" do
        result = SmarterCSV.process(StringIO.new(",b\n1,2\n"), strings_as_keys: true, duplicate_header_suffix: nil, acceleration: acceleration)
        expect(result).to eq [{ 'b' => 2 }]
      end
    end
  end
end
