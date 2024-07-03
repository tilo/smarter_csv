# frozen_string_literal: true

describe 'options processing' do
  let(:instance) { SmarterCSV::Reader.new('something', options) }
  let(:options) { {} }

  describe '#process_options' do
    context "when verbose mode" do
      let(:options) { {chunk_size: 10, verbose: true} }

      it 'prints out given options in verbose mode' do
        allow($stdout).to receive(:puts)
        expect($stdout).to receive(:puts).with(/User provided options:/)
        expect($stdout).to receive(:puts).with(/Computed options:/)
        generated_options = instance.process_options(options)
        expect(generated_options[:chunk_size]).to eq 10
      end
    end

    it 'it has the correct default options, when no input is given' do
      generated_options = instance.options
      expect(generated_options).to eq SmarterCSV::Options::DEFAULT_OPTIONS
    end

    context "when clearing out the default options" do
      let(:options) { {defaults: :none} }

      it 'lets the user clear out all default options' do
        generated_options = instance.process_options(options)
        expect(generated_options).to eq options.merge(SmarterCSV::Options::DEFAULT_OPTIONS)
      end
    end

    context "when setting invalid_byte_sequence" do
      let(:options) { { invalid_byte_sequence: nil } }

      it 'corrects :invalid_byte_sequence if nil is given' do
        generated_options = instance.process_options(invalid_byte_sequence: nil)
        expect(generated_options[:invalid_byte_sequence]).to eq ''
      end
    end

    it 'works with frozen options hash' do
      options = {chunk_size: 1}.freeze
      generated_options = instance.process_options(options)
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
              instance.process_options(invalid_options)
            end.to raise_exception(SmarterCSV::ValidationError, "[\"invalid #{opt}\"]")
          end
        end
      end

      it "does not raise an exception for #{opt} set non-empty" do
        expect do
          invalid_options = {
            opt => ' ',
          }
          instance.process_options(invalid_options)
        end.not_to raise_exception
      end
    end
  end

  describe '#default_options' do
    it 'surfaces the DEFAULT_OPTIONS hash' do
      expect(SmarterCSV.default_options).to eq SmarterCSV::Options::DEFAULT_OPTIONS
    end
  end
end
