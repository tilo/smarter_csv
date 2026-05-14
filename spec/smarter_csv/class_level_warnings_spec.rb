# frozen_string_literal: true

# Tests for SmarterCSV.warnings — thread-local warning state exposed after class-level API calls.

fixture_path = 'spec/fixtures'

describe 'SmarterCSV.warnings — class-level warning access' do
  let(:sample_csv) { "#{fixture_path}/sample.csv" }

  # Silence stderr during specs without stubbing Kernel#warn — rspec-mocks can't
  # intercept methods on prepended modules (which is how Ruby 2.7 / JRuby surface
  # warn in some setups). Replacing $stderr is portable across all engines.
  around do |example|
    original_stderr = $stderr
    $stderr = StringIO.new
    begin
      example.run
    ensure
      $stderr = original_stderr
    end
  end

  # -------------------------------------------------------------------------
  # Initial state
  # -------------------------------------------------------------------------
  describe 'before any call' do
    it 'returns an empty array' do
      Thread.current[:current_thread_recent_warnings] = nil # simulate a fresh thread
      expect(SmarterCSV.warnings).to eq([])
    end
  end

  # -------------------------------------------------------------------------
  # Populated from each class-level entry point
  # -------------------------------------------------------------------------
  describe 'after a call that emits a warning' do
    it '.each_chunk without chunk_size populates SmarterCSV.warnings' do
      SmarterCSV.each_chunk(sample_csv) { |_chunk, _i| }
      w = SmarterCSV.warnings.find { |rec| rec[:code] == :chunk_size_default }
      expect(w).not_to be_nil
      expect(w[:type]).to eq(:config)
      expect(w[:count]).to be >= 1
    end

    it '.each_chunk with chunk_size set does not warn' do
      SmarterCSV.each_chunk(sample_csv, chunk_size: 2) { |_chunk, _i| }
      expect(SmarterCSV.warnings.any? { |r| r[:code] == :chunk_size_default }).to be false
    end

    it '.parse on a clean string produces no warnings' do
      SmarterCSV.parse("name,age\nAlice,30\n")
      expect(SmarterCSV.warnings).to eq([])
    end

    it '.each on a clean file produces no warnings' do
      SmarterCSV.each(sample_csv) { |_row| }
      expect(SmarterCSV.warnings).to eq([])
    end

    it '.process on a clean file produces no warnings' do
      SmarterCSV.process(sample_csv)
      expect(SmarterCSV.warnings).to eq([])
    end
  end

  # -------------------------------------------------------------------------
  # Clearing behavior
  # -------------------------------------------------------------------------
  describe 'clearing between calls' do
    it 'clears warnings from the previous call at the start of a new call' do
      SmarterCSV.each_chunk(sample_csv) { |_chunk, _i| } # warns
      expect(SmarterCSV.warnings).not_to be_empty

      SmarterCSV.parse("a,b\n1,2\n") # clean call clears
      expect(SmarterCSV.warnings).to eq([])
    end

    it '.each clears warnings from a previous each_chunk call' do
      SmarterCSV.each_chunk(sample_csv) { |_chunk, _i| }
      expect(SmarterCSV.warnings).not_to be_empty

      SmarterCSV.each(sample_csv) { |_row| }
      expect(SmarterCSV.warnings).to eq([])
    end
  end

  # -------------------------------------------------------------------------
  # Thread isolation
  # -------------------------------------------------------------------------
  describe 'thread isolation' do
    it 'does not leak warnings across threads' do
      SmarterCSV.each_chunk(sample_csv) { |_chunk, _i| }
      expect(SmarterCSV.warnings).not_to be_empty

      warnings_in_other_thread = nil
      Thread.new do
        warnings_in_other_thread = SmarterCSV.warnings
      end.join

      expect(warnings_in_other_thread).to eq([])
    end

    it 'each thread tracks its own warnings independently' do
      results = {}

      t1 = Thread.new do
        SmarterCSV.each_chunk(sample_csv) { |_chunk, _i| } # warns
        results[:t1] = SmarterCSV.warnings.size
      end

      t2 = Thread.new do
        SmarterCSV.each_chunk(sample_csv, chunk_size: 2) { |_chunk, _i| } # no warning
        results[:t2] = SmarterCSV.warnings.size
      end

      t1.join
      t2.join

      expect(results[:t1]).to be >= 1
      expect(results[:t2]).to eq(0)
    end
  end

  # -------------------------------------------------------------------------
  # Partial state preservation on raise
  # -------------------------------------------------------------------------
  describe 'when processing raises mid-stream' do
    it 'preserves warnings collected before the raise' do
      expect do
        SmarterCSV.each_chunk(sample_csv) do |_chunk, _i| # rubocop:disable Lint/UnreachableLoop
          raise 'boom'
        end
      end.to raise_error('boom')

      # chunk_size_default warning was recorded before the block ran
      codes = SmarterCSV.warnings.map { |r| r[:code] }
      expect(codes).to include(:chunk_size_default)
    end
  end
end
