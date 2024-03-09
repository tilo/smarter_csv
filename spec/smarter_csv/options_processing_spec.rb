# frozen_string_literal: true

require 'spec_helper'

def computed_default_options(options)
  SmarterCSV.send(:compute_default_options, options)
end

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
      expect(generated_options).to eq computed_default_options({})
    end

    it 'lets the user clear out all default options' do
      options = {defaults: :none}
      generated_options = SmarterCSV.process_options(options)
      expect(generated_options).to eq options.merge(computed_default_options(options))
    end

    it 'works with frozen options hash' do
      options = {chunk_size: 1}.freeze
      generated_options = SmarterCSV.process_options(options)
      expect(generated_options[:chunk_size]).to eq 1
    end

    it 'corrects :invalid_byte_sequence if nil is given' do
      generated_options = SmarterCSV.process_options(invalid_byte_sequence: nil)
      expect(generated_options[:invalid_byte_sequence]).to eq ''
    end

    context 'when verbose option is true' do
      it 'outputs the given options' do
        options = { verbose: true }
        expect { SmarterCSV.process_options(options) }.to output(/User provided options:/).to_stdout
      end
    end

    context 'when deprecated options are used in non-v2 mode' do
      SmarterCSV::DEPRECATED_OPTIONS.each do |deprecated_option|
        context "with deprecated option #{deprecated_option}" do
          it 'outputs a warning' do
            options = { deprecated_option => true, v2_mode: false }
            expect { SmarterCSV.process_options(options) }.to output(/WARNING: SmarterCSV/).to_stdout
          end

          it 'does not output warning when deprecations are silenced' do
            options = { convert_values_to_numeric: true, v2_mode: false, silence_deprecations: true }
            expect { SmarterCSV.process_options(options) }.not_to raise_error
            expect { SmarterCSV.process_options(options) }.not_to output.to_stdout
          end
        end
      end
    end

    context 'when deprecated options are used in v2 mode' do
      SmarterCSV::DEPRECATED_OPTIONS.each do |deprecated_option|
        context "with deprecated option #{deprecated_option}" do
          it 'raises a DeprecatedOptions error' do
            options = { deprecated_option => true, v2_mode: true }
            expect { SmarterCSV.process_options(options) }.to raise_error(SmarterCSV::DeprecatedOptions)
          end
        end
      end
    end

    context 'when silence_deprecations option is true' do
      it 'does not raise a DeprecatedOptions error nor output a warning even with deprecated options' do
        options = { convert_values_to_numeric: true, v2_mode: true, silence_deprecations: true }
        expect { SmarterCSV.process_options(options) }.not_to raise_error
        expect { SmarterCSV.process_options(options) }.not_to output.to_stdout
      end
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
      expect(SmarterCSV.default_options).to eq computed_default_options({})
    end
  end

  describe 'v2_mode' do
    it 'defaults to false, aka v1' do
      expect(SmarterCSV.default_options[:v2_mode]).to eq false
    end

    it 'can be switched to v2_mode' do
      parsed_options = SmarterCSV.process_options(v2_mode: true)
      expect(parsed_options[:v2_mode]).to eq true
    end
  end
end
