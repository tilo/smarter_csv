# frozen_string_literal: true

fixture_path = 'spec/fixtures'

describe 'Instrumentation hooks (on_start, on_chunk, on_complete)' do
  let(:basic_csv) { "#{fixture_path}/basic.csv" }

  # ----------------------------------------------------------------
  # Validation
  # ----------------------------------------------------------------
  describe 'option validation' do
    it 'accepts nil (default — no hooks)' do
      expect { SmarterCSV.process(basic_csv, on_start: nil, on_chunk: nil, on_complete: nil) }.not_to raise_error
    end

    it 'accepts callables' do
      noop = ->(_) {}
      expect { SmarterCSV.process(basic_csv, on_start: noop, on_chunk: noop, on_complete: noop) }.not_to raise_error
    end

    %i[on_start on_chunk on_complete].each do |hook|
      it "raises ValidationError when #{hook} is not callable" do
        expect { SmarterCSV.process(basic_csv, hook => :not_a_callable) }
          .to raise_error(SmarterCSV::ValidationError, /invalid #{hook}/)
      end
    end
  end

  # ----------------------------------------------------------------
  # on_start
  # ----------------------------------------------------------------
  describe 'on_start' do
    it 'fires once before any rows are processed' do
      calls = []
      SmarterCSV.process(basic_csv, on_start: ->(info) { calls << info })
      expect(calls.size).to eq 1
    end

    it 'receives file path and size when input is a filename' do
      received = nil
      SmarterCSV.process(basic_csv, on_start: ->(info) { received = info })
      expect(received[:input]).to eq basic_csv
      expect(received[:file_size]).to be_a(Integer)
      expect(received[:file_size]).to be > 0
    end

    it 'receives IO class name when input is an IO object' do
      received = nil
      File.open(basic_csv) do |f|
        SmarterCSV.process(f, on_start: ->(info) { received = info })
      end
      expect(received[:input]).to eq 'File'
      expect(received[:file_size]).to be_nil
    end

    it 'includes col_sep and row_sep in the payload' do
      received = nil
      SmarterCSV.process(basic_csv, on_start: ->(info) { received = info })
      expect(received).to have_key(:col_sep)
      expect(received).to have_key(:row_sep)
    end

    it 'fires before rows are yielded' do
      order = []
      SmarterCSV.process(basic_csv,
        on_start: ->(_) { order << :start },
        chunk_size: 1,
        on_chunk: ->(_) { order << :chunk },
      )
      expect(order.first).to eq :start
    end
  end

  # ----------------------------------------------------------------
  # on_complete
  # ----------------------------------------------------------------
  describe 'on_complete' do
    it 'fires once after all rows are processed' do
      calls = []
      SmarterCSV.process(basic_csv, on_complete: ->(stats) { calls << stats })
      expect(calls.size).to eq 1
    end

    it 'receives total_rows, duration, total_chunks, and bad_rows' do
      received = nil
      SmarterCSV.process(basic_csv, on_complete: ->(stats) { received = stats })
      expect(received[:total_rows]).to be_a(Integer)
      expect(received[:total_rows]).to be > 0
      expect(received[:duration]).to be_a(Float)
      expect(received[:duration]).to be >= 0
      expect(received[:total_chunks]).to eq 0   # non-chunked mode
      expect(received[:bad_rows]).to eq 0
    end

    it 'fires after on_start' do
      order = []
      SmarterCSV.process(basic_csv,
        on_start:    ->(_) { order << :start },
        on_complete: ->(_) { order << :complete },
      )
      expect(order).to eq %i[start complete]
    end

    it 'duration is positive and reflects real elapsed time' do
      received = nil
      SmarterCSV.process(basic_csv, on_complete: ->(s) { received = s })
      expect(received[:duration]).to be > 0
    end
  end

  # ----------------------------------------------------------------
  # on_chunk (only fires in chunked mode)
  # ----------------------------------------------------------------
  describe 'on_chunk' do
    it 'does not fire when chunk_size is not set' do
      calls = []
      SmarterCSV.process(basic_csv, on_chunk: ->(_) { calls << true })
      expect(calls).to be_empty
    end

    it 'fires once per chunk in chunked mode' do
      row_count = SmarterCSV.process(basic_csv).size
      chunk_size = 2
      expected_chunks = (row_count.to_f / chunk_size).ceil

      calls = []
      SmarterCSV.process(basic_csv, chunk_size: chunk_size, on_chunk: ->(info) { calls << info })
      expect(calls.size).to eq expected_chunks
    end

    it 'receives chunk_number (1-based), rows_in_chunk, and total_rows_so_far' do
      calls = []
      SmarterCSV.process(basic_csv, chunk_size: 1, on_chunk: ->(info) { calls << info })
      expect(calls.first[:chunk_number]).to eq 1
      expect(calls.first[:rows_in_chunk]).to eq 1
      expect(calls.first[:total_rows_so_far]).to be > 0
      expect(calls.last[:chunk_number]).to eq calls.size
    end

    it 'fires before the block receives the chunk' do
      order = []
      SmarterCSV.process(basic_csv, chunk_size: 2,
        on_chunk: ->(_) { order << :hook },
      ) { |_chunk| order << :block }
      # hook always precedes its corresponding block call
      order.each_slice(2) { |pair| expect(pair).to eq %i[hook block] }
    end

    it 'total_rows_so_far is cumulative across chunks' do
      totals = []
      SmarterCSV.process(basic_csv, chunk_size: 1, on_chunk: ->(info) { totals << info[:total_rows_so_far] })
      expect(totals).to eq totals.sort
      expect(totals.uniq.size).to eq totals.size
    end
  end

  # ----------------------------------------------------------------
  # on_complete reflects chunked totals
  # ----------------------------------------------------------------
  describe 'on_complete in chunked mode' do
    it 'total_chunks equals the number of on_chunk calls' do
      chunk_calls = 0
      complete_info = nil
      SmarterCSV.process(basic_csv, chunk_size: 2,
        on_chunk:    ->(_) { chunk_calls += 1 },
        on_complete: ->(s) { complete_info = s },
      )
      expect(complete_info[:total_chunks]).to eq chunk_calls
    end
  end
end
