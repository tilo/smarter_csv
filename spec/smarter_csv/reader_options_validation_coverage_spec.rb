# frozen_string_literal: true

# Additional coverage for reader_options.rb:
# - required_headers deprecation path
# - quote_escaping validation
# - user_provided_headers auto-setting headers_in_file

describe 'options validation coverage' do
  let(:instance) { SmarterCSV::Reader.new('something', options) }
  let(:options) { {} }

  describe 'constants invariant' do
    it 'ensures MAX_AUTO_ROW_SEP_CHARS == MAX_BUFFER_SIZE to prevent accidental divergence' do
      max_arc = SmarterCSV::AutoDetection::MAX_AUTO_ROW_SEP_CHARS
      max_bs = SmarterCSV::PeekableIO::MAX_BUFFER_SIZE
      expect(max_arc).to eq(max_bs)
    end
  end

  describe 'required_headers deprecation' do
    it 'converts required_headers to required_keys with a deprecation warning' do
      expect do
        generated_options = instance.process_options(required_headers: [:name, :email])
        expect(generated_options[:required_keys]).to eq [:name, :email]
        expect(generated_options[:required_headers]).to be_nil
      end.to output(/DEPRECATION WARNING.*required_keys/).to_stderr
    end

    it 'does not overwrite existing required_keys when required_headers is also given' do
      expect do
        generated_options = instance.process_options(required_headers: [:old], required_keys: [:new])
        # required_keys was already set, so it should NOT be overwritten
        expect(generated_options[:required_keys]).to eq [:new]
      end.to output(/DEPRECATION WARNING/).to_stderr
    end
  end

  describe 'quote_escaping validation' do
    it 'accepts :double_quotes' do
      expect do
        instance.process_options(quote_escaping: :double_quotes)
      end.not_to raise_error
    end

    it 'accepts :backslash' do
      expect do
        instance.process_options(quote_escaping: :backslash)
      end.not_to raise_error
    end

    it 'accepts :auto' do
      expect do
        instance.process_options(quote_escaping: :auto)
      end.not_to raise_error
    end

    it 'raises ValidationError for invalid quote_escaping value' do
      expect do
        instance.process_options(quote_escaping: :invalid)
      end.to raise_error(SmarterCSV::ValidationError, /invalid quote_escaping/)
    end

    it 'raises ValidationError for string quote_escaping' do
      expect do
        instance.process_options(quote_escaping: 'double_quotes')
      end.to raise_error(SmarterCSV::ValidationError, /invalid quote_escaping/)
    end
  end

  describe 'user_provided_headers auto-sets headers_in_file' do
    it 'sets headers_in_file to false when user_provided_headers given without explicit headers_in_file' do
      expect do
        generated_options = instance.process_options(user_provided_headers: [:a, :b])
        expect(generated_options[:headers_in_file]).to eq false
      end.to output(/WARNING.*headers_in_file/).to_stderr
    end

    it 'does not override explicit headers_in_file when user_provided_headers given' do
      generated_options = instance.process_options(user_provided_headers: [:a, :b], headers_in_file: true)
      expect(generated_options[:headers_in_file]).to eq true
    end
  end

  describe 'auto_row_sep_chars validation' do
    it 'warns and uses the default for a non-integer type' do
      opts = nil
      expect do
        opts = instance.process_options(auto_row_sep_chars: 'large')
      end.to output(/WARNING.*auto_row_sep_chars/).to_stderr
      expect(opts[:auto_row_sep_chars]).to eq SmarterCSV::Reader::Options::DEFAULT_OPTIONS[:auto_row_sep_chars]
    end

    it 'warns and uses the default for a negative value' do
      opts = nil
      expect do
        opts = instance.process_options(auto_row_sep_chars: -1)
      end.to output(/WARNING.*auto_row_sep_chars/).to_stderr
      expect(opts[:auto_row_sep_chars]).to eq SmarterCSV::Reader::Options::DEFAULT_OPTIONS[:auto_row_sep_chars]
    end

    it 'warns and uses the default for zero' do
      opts = nil
      expect do
        opts = instance.process_options(auto_row_sep_chars: 0)
      end.to output(/WARNING.*auto_row_sep_chars/).to_stderr
      expect(opts[:auto_row_sep_chars]).to eq SmarterCSV::Reader::Options::DEFAULT_OPTIONS[:auto_row_sep_chars]
    end

    it 'warns and uses the default for a positive value below the minimum' do
      opts = nil
      expect do
        opts = instance.process_options(auto_row_sep_chars: 100)
      end.to output(/WARNING.*auto_row_sep_chars/).to_stderr
      expect(opts[:auto_row_sep_chars]).to eq SmarterCSV::Reader::Options::DEFAULT_OPTIONS[:auto_row_sep_chars]
    end

    it 'accepts a value at the minimum (8192)' do
      expect { instance.process_options(auto_row_sep_chars: 8_192) }.not_to raise_error
    end

    it 'accepts a value above the minimum' do
      expect { instance.process_options(auto_row_sep_chars: 16_384) }.not_to raise_error
    end

    it 'warns and clamps to MAX_AUTO_ROW_SEP_CHARS for values exceeding the ceiling' do
      max_arc = SmarterCSV::AutoDetection::MAX_AUTO_ROW_SEP_CHARS
      expect do
        instance.process_options(auto_row_sep_chars: max_arc + 1_000)
      end.to output(/WARNING.*auto_row_sep_chars/).to_stderr
      expect(instance.options[:auto_row_sep_chars]).to eq max_arc
    end

    it 'warns and clamps to MAX_AUTO_ROW_SEP_CHARS for very large values' do
      max_arc = SmarterCSV::AutoDetection::MAX_AUTO_ROW_SEP_CHARS
      expect do
        instance.process_options(auto_row_sep_chars: 1_000_000)
      end.to output(/WARNING.*auto_row_sep_chars/).to_stderr
      expect(instance.options[:auto_row_sep_chars]).to eq max_arc
    end

    it 'accepts a value at the maximum without warning' do
      max_arc = SmarterCSV::AutoDetection::MAX_AUTO_ROW_SEP_CHARS
      expect do
        instance.process_options(auto_row_sep_chars: max_arc, verbose: :quiet)
      end.not_to raise_error
      expect(instance.options[:auto_row_sep_chars]).to eq max_arc
    end
  end

  describe 'buffer_size validation' do
    let(:default_bs) { SmarterCSV::Reader::Options::DEFAULT_OPTIONS[:buffer_size] }
    let(:min_bs)     { SmarterCSV::PeekableIO::MIN_BUFFER_SIZE }
    let(:max_bs)     { SmarterCSV::PeekableIO::MAX_BUFFER_SIZE }

    it 'uses default for nil (treated as "unset", no warning)' do
      expect { instance.process_options(buffer_size: nil, verbose: :quiet) }.not_to raise_error
      expect(instance.options[:buffer_size]).to eq default_bs
    end

    it 'uses default for 0 (treated as "unset", no warning)' do
      expect { instance.process_options(buffer_size: 0, verbose: :quiet) }.not_to raise_error
      expect(instance.options[:buffer_size]).to eq default_bs
    end

    it 'warns and uses default for a non-integer type' do
      expect { instance.process_options(buffer_size: '1024') }.to output(/invalid buffer_size/).to_stderr
      expect(instance.options[:buffer_size]).to eq default_bs
    end

    it 'warns when value is below MIN_BUFFER_SIZE' do
      # MIN clamp brings buffer_size to 4096; cross-validation then bumps to 8192
      # because auto_row_sep_chars defaults to 8192. Both warnings fire.
      expect { instance.process_options(buffer_size: 100) }.to output(/below minimum/).to_stderr
      expect(instance.options[:buffer_size]).to be >= min_bs
    end

    it 'warns and clamps to MAX_BUFFER_SIZE for values above the ceiling' do
      expect { instance.process_options(buffer_size: 10_000_000) }.to output(/exceeds maximum/).to_stderr
      expect(instance.options[:buffer_size]).to eq max_bs
    end

    it 'accepts a value within bounds without warning' do
      expect { instance.process_options(buffer_size: 16_384, verbose: :quiet) }.not_to raise_error
      expect(instance.options[:buffer_size]).to eq 16_384
    end

    it 'bumps buffer_size when it is below auto_row_sep_chars' do
      # buffer_size = 4096 (at MIN), auto_row_sep_chars = 16384.
      # Cross-validation triggers: bump = max(2 * 4096, MIN_AUTO_ROW_SEP_CHARS) = max(8192, 8192) = 8192.
      expect do
        instance.process_options(buffer_size: 4_096, auto_row_sep_chars: 16_384)
      end.to output(/bumping buffer_size/).to_stderr
      expect(instance.options[:buffer_size]).to eq 8_192
    end

    it 'does not bump when buffer_size is already >= auto_row_sep_chars' do
      expect do
        instance.process_options(buffer_size: 16_384, auto_row_sep_chars: 8_192, verbose: :quiet)
      end.not_to output(/bumping buffer_size/).to_stderr
      expect(instance.options[:buffer_size]).to eq 16_384
    end

    it 'suppresses all buffer_size warnings under verbose: :quiet' do
      expect do
        instance.process_options(buffer_size: 100, verbose: :quiet)
      end.not_to output.to_stderr
      expect(instance.options[:buffer_size]).to be >= min_bs
    end

    it 'clamps bumped buffer_size to MAX when it would exceed the ceiling' do
      # buffer_size = 50_000, auto_row_sep_chars = 60_000
      # Without fix: bump = max(2 * 50_000, MIN_AUTO_ROW_SEP_CHARS) = 100_000 (exceeds 65_536)
      # With fix: should clamp to 65_536
      expect do
        instance.process_options(buffer_size: 50_000, auto_row_sep_chars: 60_000)
      end.to output(/bumping buffer_size/).to_stderr
      expect(instance.options[:buffer_size]).to eq max_bs
    end

    it 'clamps bumped buffer_size with different overflow scenario' do
      # buffer_size = 40_000, auto_row_sep_chars = 50_000
      # Bump would be: 2 * 40_000 = 80_000 (exceeds 65_536)
      # Should clamp to 65_536
      expect do
        instance.process_options(buffer_size: 40_000, auto_row_sep_chars: 50_000)
      end.to output(/bumping buffer_size/).to_stderr
      expect(instance.options[:buffer_size]).to eq max_bs
    end

    it 'allows small buffer_size bump that does not exceed the ceiling' do
      # buffer_size = 20_000, auto_row_sep_chars = 30_000
      # Bump would be: 2 * 20_000 = 40_000 (within 65_536)
      # Should succeed without clamping to max
      expect do
        instance.process_options(buffer_size: 20_000, auto_row_sep_chars: 30_000)
      end.to output(/bumping buffer_size/).to_stderr
      expect(instance.options[:buffer_size]).to eq 40_000
      expect(instance.options[:buffer_size]).to be <= max_bs
    end
  end

  describe 'option_valid?' do
    it 'accepts :auto as a valid symbol' do
      expect do
        instance.process_options(row_sep: :auto)
      end.not_to raise_error
    end

    it 'rejects non-auto symbols' do
      expect do
        instance.process_options(col_sep: :tab)
      end.to raise_error(SmarterCSV::ValidationError)
    end

    it 'rejects numeric values' do
      expect do
        instance.process_options(quote_char: 1)
      end.to raise_error(SmarterCSV::ValidationError)
    end
  end
end
