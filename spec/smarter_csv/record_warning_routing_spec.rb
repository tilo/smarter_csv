# frozen_string_literal: true

# Tests for Reader#record_warning sink routing:
#   - No Rails.logger → emits via Kernel#warn (severity is ignored)
#   - Rails.logger present → emits via Rails.logger at the given severity
#   - severity is passed by the caller (default :warn); type is purely a
#     semantic grouping for callers iterating reader.warnings.

require 'stringio'

describe 'SmarterCSV::Reader#record_warning — sink routing' do
  let(:csv) { "a,b\n1,2\n" }

  # -------------------------------------------------------------------------
  # Non-Rails branch: uses Kernel#warn regardless of severity
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

    it 'falls back to Kernel#warn even when severity: :error' do
      reader = SmarterCSV::Reader.new(StringIO.new(csv))

      expect(reader).to receive(:warn).with(a_string_including('SmarterCSV:', 'oops'))
      reader.send(:record_warning, type: :row_sep, code: :no_clear_row_sep, severity: :error) { 'oops' }
    end

    it 'records the severity on the warning record' do
      reader = SmarterCSV::Reader.new(StringIO.new(csv))
      allow(reader).to receive(:warn)

      reader.send(:record_warning, type: :row_sep, code: :no_clear_row_sep, severity: :error) { 'oops' }
      record = reader.warnings.find { |w| w[:code] == :no_clear_row_sep }
      expect(record[:severity]).to eq(:error)
    end
  end

  # -------------------------------------------------------------------------
  # Rails branch: uses Rails.logger at caller-supplied severity
  # -------------------------------------------------------------------------
  describe 'with Rails.logger present' do
    let(:fake_logger) { instance_double('Logger', debug: nil, info: nil, warn: nil, error: nil, fatal: nil) }

    before do
      stub_const('Rails', Class.new)
      allow(Rails).to receive(:logger).and_return(fake_logger)
    end

    it 'has_rails_logger is true when Rails constant and logger are both present' do
      reader = SmarterCSV::Reader.new(StringIO.new(csv))
      expect(reader.has_rails_logger).to be true
    end

    it 'defaults to :warn severity when none is passed' do
      reader = SmarterCSV::Reader.new(StringIO.new(csv))

      expect(fake_logger).to receive(:warn).with(a_string_including('SmarterCSV:', 'default'))
      expect(fake_logger).not_to receive(:info)

      reader.send(:record_warning, type: :config, code: :test_code) { 'default' }
    end

    it 'routes at :error when severity: :error' do
      reader = SmarterCSV::Reader.new(StringIO.new(csv))

      expect(fake_logger).to receive(:error).with(a_string_including('SmarterCSV:', 'silent miss'))
      reader.send(:record_warning, type: :row_sep, code: :no_clear_row_sep, severity: :error) { 'silent miss' }
    end

    it 'routes at :info when severity: :info' do
      reader = SmarterCSV::Reader.new(StringIO.new(csv))

      expect(fake_logger).to receive(:info).with(a_string_including('SmarterCSV:', 'fyi'))
      reader.send(:record_warning, type: :config, code: :hint, severity: :info) { 'fyi' }
    end

    it 'routes at :debug when severity: :debug' do
      reader = SmarterCSV::Reader.new(StringIO.new(csv))

      expect(fake_logger).to receive(:debug).with(a_string_including('SmarterCSV:', 'noise'))
      reader.send(:record_warning, type: :config, code: :verbose, severity: :debug) { 'noise' }
    end

    it 'never calls Kernel#warn when Rails.logger is present' do
      reader = SmarterCSV::Reader.new(StringIO.new(csv))

      expect(reader).not_to receive(:warn)
      reader.send(:record_warning, type: :config, code: :test_code) { 'hi' }
    end

    it 'records the severity on the warning record' do
      reader = SmarterCSV::Reader.new(StringIO.new(csv))

      reader.send(:record_warning, type: :row_sep, code: :no_clear_row_sep, severity: :error) { 'silent miss' }
      record = reader.warnings.find { |w| w[:code] == :no_clear_row_sep }
      expect(record[:severity]).to eq(:error)
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
      expect(fake_logger).not_to receive(:warn)
      reader.send(:record_warning, type: :config, code: :test_code) { 'hi' }
    end
  end
end
