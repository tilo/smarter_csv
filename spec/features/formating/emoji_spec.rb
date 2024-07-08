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
