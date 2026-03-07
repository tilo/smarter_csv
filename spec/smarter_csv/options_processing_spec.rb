# frozen_string_literal: true

describe 'options processing' do
  let(:instance) { SmarterCSV::Reader.new('something', options) }
  let(:options) { {} }

  describe '#process_options' do
    context "when verbose mode" do
      let(:options) { {chunk_size: 10, verbose: true} }

      it 'prints out given options in verbose mode (verbose: true → :debug)' do
        expect do
          generated_options = instance.process_options(options)
          expect(generated_options[:chunk_size]).to eq 10
        end.to output(/DEPRECATION WARNING.*User provided options:.*Computed options:/m).to_stderr
      end
    end

    describe 'verbose level normalization' do
      # Use a clean instance (no verbose in constructor options) so only the
      # process_options call under test contributes output.
      let(:clean) { SmarterCSV::Reader.new('something', {}) }

      it 'normalizes verbose: true to :debug with a deprecation warning' do
        expect do
          expect(clean.process_options(verbose: true)[:verbose]).to eq :debug
        end.to output(/DEPRECATION WARNING.*verbose: true.*verbose: :debug/m).to_stderr
      end

      it 'normalizes verbose: false to :normal with a deprecation warning' do
        expect do
          expect(clean.process_options(verbose: false)[:verbose]).to eq :normal
        end.to output(/DEPRECATION WARNING.*verbose: false.*verbose: :normal/m).to_stderr
      end

      it 'normalizes verbose: nil to :normal silently (nil means not set)' do
        expect do
          expect(clean.process_options(verbose: nil)[:verbose]).to eq :normal
        end.not_to output(/DEPRECATION WARNING/).to_stderr
      end

      it 'keeps :quiet as :quiet without warning' do
        expect do
          expect(clean.process_options(verbose: :quiet)[:verbose]).to eq :quiet
        end.not_to output(/DEPRECATION/).to_stderr
      end

      it 'keeps :debug as :debug without warning' do
        expect do
          expect(clean.process_options(verbose: :debug)[:verbose]).to eq :debug
        end.not_to output(/DEPRECATION/).to_stderr
      end

      it 'normalizes an unknown verbose value to :normal with a warning' do
        expect do
          expect(clean.process_options(verbose: :loud)[:verbose]).to eq :normal
        end.to output(/WARNING.*unknown verbose value.*:loud/i).to_stderr
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
