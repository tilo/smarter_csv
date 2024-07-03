# frozen_string_literal: true

fixture_path = 'spec/fixtures'

[true, false].each do |bool|
  describe "fulfills basic tests with#{bool ? ' C-' : 'out '}acceleration" do
    let(:options) { { acceleration: bool } }
    let(:reader) { SmarterCSV::Reader.new(basic_file, options) }
    let(:basic_file) { "#{fixture_path}/basic.csv" }

    describe 'basic CSV processing' do
      # works only when testing locally
      unless ENV['CI']
        it 'compiles the acceleration' do
          expect(reader.has_acceleration).to eq true
        end
      end

      context 'with basic CSV file' do
        it 'loads_basic_csv_file' do
          data = reader.process
          expect(data.size).to eq 5

          data.each do |h|
            h.each_key do |key|
              # all the keys should be symbols
              expect(key.class).to eq Symbol

              expect(%i[first_name last_name dogs cats birds fish]).to include(key)
            end
            expect(h.size).to be <= 6
          end
        end

        it 'loads_basic_csv_file from Rails' do
          stub_const('Rails', true)
          data = reader.process
          expect(data.size).to eq 5

          data.each do |h|
            h.each_key do |key|
              # all the keys should be symbols
              expect(key.class).to eq Symbol

              expect(%i[first_name last_name dogs cats birds fish]).to include(key)
            end
            expect(h.size).to be <= 6
          end
        end

        context 'with full user_provided_headers' do
          let(:options) { super().merge({user_provided_headers: %i[a b c d e f]}) }

          it 'replaces headers with user_provided_headers' do
            data = reader.process
            expect(data.size).to eq 5

            expect(reader.raw_header).to eq "First Name,Last Name,Dogs,Cats,Birds,Fish\n"
            expect(reader.headers).to eq %i[a b c d e f]
          end
        end

        context 'with partial user_provided_headers' do
          let(:options) { super().merge({user_provided_headers: %i[a b c d e]}) }

          it 'raises an exception if the number of user_provided_headers is incorrect' do
            expect do
              reader.process
            end.to raise_exception(SmarterCSV::HeaderSizeMismatch)
          end
        end

        context 'with empty user_provided_headers' do
          let(:options) { super().merge({user_provided_headers: []}) }

          it 'raises an exception if the user_provided_headers is empty' do
            expect do
              reader.process
            end.to raise_exception(SmarterCSV::IncorrectOption, /ERROR: incorrect format for user_provided_headers! Expecting array with headers/)
          end
        end

        context 'with incorrect user_provided_headers' do
          let(:options) { super().merge({user_provided_headers: {}}) }

          it 'raises an exception if the user_provided_headers is of incorrect type' do
            expect do
              reader.process
            end.to raise_exception(SmarterCSV::IncorrectOption, /ERROR: incorrect format for user_provided_headers! Expecting array with headers/)
          end
        end
      end
    end
  end
end
