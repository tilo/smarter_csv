# frozen_string_literal: true

describe 'options processing' do
  describe '#process_options' do
    it 'prints out given options in verbose mode' do
      options = {chunk_size: 10, verbose: true}
      allow($stdout).to receive(:puts)
      expect($stdout).to receive(:puts).with(/User provided options:/)
      expect($stdout).to receive(:puts).with(/Computed options:/)
      generated_options = SmarterCSV.process_options(options)
      expect(generated_options[:chunk_size]).to eq 10
    end

    it 'it has the correct default options, when no input is given' do
      generated_options = SmarterCSV.process_options({})
      expect(generated_options).to eq SmarterCSV::DEFAULT_OPTIONS
    end

    it 'lets the user clear out all default options' do
      options = {defaults: :none}
      generated_options = SmarterCSV.process_options(options)
      expect(generated_options).to eq options.merge(SmarterCSV::DEFAULT_OPTIONS)
    end

    it 'corrects :invalid_byte_sequence if nil is given' do
      generated_options = SmarterCSV.process_options(invalid_byte_sequence: nil)
      expect(generated_options[:invalid_byte_sequence]).to eq ''
    end

    it 'works with frozen options hash' do
      options = {chunk_size: 1}.freeze
      generated_options = SmarterCSV.process_options(options)
      expect(generated_options[:chunk_size]).to eq 1
    end
  end

  describe '#validate_options!' do
    [:row_sep, :col_sep, :quote_char].each do |opt|
      # empty values
      [nil, ''].each do |val|
        context "with invalid value #{val}" do
          it "raises an exception for #{opt} set #{val}" do
            expect do
              invalid_options = {
                opt => val,
              }
              SmarterCSV.process_options(invalid_options)
            end.to raise_exception(SmarterCSV::ValidationError, "[\"invalid #{opt}\"]")
          end
        end
      end

      it "does not raise an exception for #{opt} set non-empty" do
        expect do
          invalid_options = {
            opt => ' ',
          }
          SmarterCSV.process_options(invalid_options)
        end.not_to raise_exception
      end
    end
  end

  describe '#default_options' do
    it 'surfaces the DEFAULT_OPTIONS hash' do
      expect(SmarterCSV.default_options).to eq SmarterCSV::DEFAULT_OPTIONS
    end
  end
end
