# frozen_string_literal: true

require_relative '../../ext/smarter_csv/cpu_flags'

# Contract for the pure (mkmf-free) CPU-optimization flag selector used by
# ext/smarter_csv/extconf.rb. It maps SMARTER_CSV_PERFORMANCE to the list of
# host flags to append, asking the supplied `accepts` predicate (which wraps
# the compiler probe in the real build) whether each candidate flag compiles.
#
# Safety contract behind these tests: the default (and any unknown value) must
# NEVER add a host-specific instruction-set flag (-march/-mcpu native), because
# that is what makes a binary crash with "Illegal instruction" on a CPU that
# lacks the build host's instructions (issue #343).
describe SmarterCSV::CpuFlags do
  let(:accepts_all)  { ->(_flag) { true } }
  let(:accepts_none) { ->(_flag) { false } }

  def select(level, accepts: accepts_all)
    described_class.select(level, accepts: accepts)
  end

  describe 'portable (the default)' do
    it 'defaults to portable when the value is nil' do
      result = select(nil)
      expect(result[:level]).to eq 'portable'
      expect(result[:flags]).to eq []
      expect(result[:warning]).to be_nil
    end

    it 'defaults to portable when the value is empty' do
      expect(select('')[:level]).to eq 'portable'
    end

    it 'adds no host flags even when the compiler would accept every flag' do
      expect(select('portable', accepts: accepts_all)[:flags]).to eq []
    end

    it 'is case-insensitive' do
      expect(select('PORTABLE')[:level]).to eq 'portable'
    end

    it 'ignores surrounding whitespace' do
      expect(select('  portable  ')[:level]).to eq 'portable'
    end
  end

  describe 'tuned' do
    it 'adds -mtune=native when the compiler accepts it' do
      expect(select('tuned', accepts: accepts_all)[:flags]).to eq ['-mtune=native']
    end

    it 'adds nothing when the compiler rejects -mtune=native (e.g. MSVC)' do
      expect(select('tuned', accepts: accepts_none)[:flags]).to eq []
    end

    it 'never adds an instruction-set flag (-march/-mcpu)' do
      flags = select('tuned', accepts: accepts_all)[:flags]
      expect(flags).not_to include('-march=native')
      expect(flags).not_to include('-mcpu=native')
    end
  end

  describe 'max' do
    it 'prefers -march=native when the compiler accepts it' do
      expect(select('max', accepts: accepts_all)[:flags]).to eq ['-march=native']
    end

    it 'falls back to -mcpu=native when -march=native is rejected (e.g. Clang on ARM)' do
      accepts = ->(flag) { flag != '-march=native' }
      expect(select('max', accepts: accepts)[:flags]).to eq ['-mcpu=native']
    end

    it 'falls back to -mtune=native when both -march and -mcpu are rejected' do
      accepts = ->(flag) { flag == '-mtune=native' }
      expect(select('max', accepts: accepts)[:flags]).to eq ['-mtune=native']
    end

    it 'adds nothing when the compiler rejects every candidate (e.g. MSVC)' do
      expect(select('max', accepts: accepts_none)[:flags]).to eq []
    end
  end

  describe 'unknown / typo values' do
    it 'falls back to portable so a typo can only ever be slower, never non-portable' do
      result = select('fast')
      expect(result[:level]).to eq 'portable'
      expect(result[:flags]).to eq []
    end

    it 'warns, naming the bad value and the level it fell back to' do
      warning = select('fast')[:warning]
      expect(warning).to include('fast')
      expect(warning).to include('portable')
    end
  end
end
