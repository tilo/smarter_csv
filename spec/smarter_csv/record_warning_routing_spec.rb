# frozen_string_literal: true

# Tests for Reader#record_warning sink routing:
#   - No Rails.logger → emits via Kernel#warn
#   - Rails.logger present → emits via Rails.logger with severity per type

require 'stringio'

describe 'SmarterCSV::Reader#record_warning — sink routing' do
  let(:csv) { "a,b\n1,2\n" }

  # -------------------------------------------------------------------------
  # Non-Rails branch: uses Kernel#warn
  # -------------------------------------------------------------------------
  describe 'without Rails' do
    it 'routes every warning to Kernel#warn' do
      reader = SmarterCSV::Reader.new(StringIO.new(csv))
      expect(reader.has_rails_logger).to be_falsey

      expect(reader).to receive(:warn).with(a_string_including('SmarterCSV:', 'boom'))
      reader.send(:record_warning, type: :config, code: :test_code) { 'boom' }
    end

    it 'still records the warning in @warnings regardless of sink' do
      reader = SmarterCSV::Reader.new(StringIO.new(csv))
      allow(reader).to receive(:warn)

      reader.send(:record_warning, type: :config, code: :test_code) { 'boom' }
      expect(reader.warnings.map { |w| w[:code] }).to include(:test_code)
    end
  end

  # -------------------------------------------------------------------------
  # Rails branch: uses Rails.logger with severity mapping
  # -------------------------------------------------------------------------
  describe 'with Rails.logger present' do
    let(:fake_logger) { instance_double('Logger', info: nil, warn: nil, error: nil) }

    before do
      stub_const('Rails', Class.new)
      allow(Rails).to receive(:logger).and_return(fake_logger)
    end

    it 'has_rails_logger is true when Rails constant and logger are both present' do
      reader = SmarterCSV::Reader.new(StringIO.new(csv))
      expect(reader.has_rails_logger).to be true
    end

    it 'routes :config warnings at :info severity' do
      reader = SmarterCSV::Reader.new(StringIO.new(csv))

      expect(fake_logger).to receive(:info).with(a_string_including('SmarterCSV:', 'chunk hint'))
      expect(fake_logger).not_to receive(:warn)

      reader.send(:record_warning, type: :config, code: :chunk_hint) { 'chunk hint' }
    end

    it 'routes :deprecation warnings at :warn severity' do
      reader = SmarterCSV::Reader.new(StringIO.new(csv))

      expect(fake_logger).to receive(:warn).with(a_string_including('SmarterCSV:', 'gone soon'))
      reader.send(:record_warning, type: :deprecation, code: :old_method) { 'gone soon' }
    end

    it 'routes :row_sep warnings at :warn severity' do
      reader = SmarterCSV::Reader.new(StringIO.new(csv))

      expect(fake_logger).to receive(:warn).with(a_string_including('SmarterCSV:', 'ambiguous'))
      reader.send(:record_warning, type: :row_sep, code: :no_clear_row_sep) { 'ambiguous' }
    end

    it 'routes :encoding warnings at :warn severity' do
      reader = SmarterCSV::Reader.new(StringIO.new(csv))

      expect(fake_logger).to receive(:warn).with(a_string_including('SmarterCSV:', 'utf8'))
      reader.send(:record_warning, type: :encoding, code: :utf8_missing_binary_mode) { 'utf8' }
    end

    it 'falls back to :warn severity for unknown types' do
      reader = SmarterCSV::Reader.new(StringIO.new(csv))

      expect(fake_logger).to receive(:warn).with(a_string_including('SmarterCSV:', 'mystery'))
      reader.send(:record_warning, type: :some_future_type, code: :whatever) { 'mystery' }
    end

    it 'never calls Kernel#warn when Rails.logger is present' do
      reader = SmarterCSV::Reader.new(StringIO.new(csv))

      expect(reader).not_to receive(:warn)
      reader.send(:record_warning, type: :config, code: :chunk_hint) { 'chunk hint' }
    end
  end

  # -------------------------------------------------------------------------
  # Rails defined but no logger → fall back to warn
  # -------------------------------------------------------------------------
  describe 'with Rails defined but no logger' do
    before do
      stub_const('Rails', Class.new)
      allow(Rails).to receive(:logger).and_return(nil)
    end

    it 'has_rails_logger is false and emissions go to Kernel#warn' do
      reader = SmarterCSV::Reader.new(StringIO.new(csv))
      expect(reader.has_rails).to be true           # Rails constant exists
      expect(reader.has_rails_logger).to be false   # but no usable logger

      expect(reader).to receive(:warn).with(a_string_including('SmarterCSV:', 'nope'))
      reader.send(:record_warning, type: :config, code: :test_code) { 'nope' }
    end
  end

  # -------------------------------------------------------------------------
  # @has_rails_logger is cached at init — doesn't re-check per call
  # -------------------------------------------------------------------------
  describe 'detection is cached at construct time' do
    it 'Rails appearing after Reader init does not flip the branch' do
      reader = SmarterCSV::Reader.new(StringIO.new(csv))
      expect(reader.has_rails_logger).to be_falsey

      # Rails shows up mid-run — reader sticks with the branch it picked.
      stub_const('Rails', Class.new)
      fake_logger = instance_double('Logger', info: nil, warn: nil)
      allow(Rails).to receive(:logger).and_return(fake_logger)

      expect(reader).to receive(:warn)
      expect(fake_logger).not_to receive(:info)
      reader.send(:record_warning, type: :config, code: :test_code) { 'hi' }
    end
  end
end
