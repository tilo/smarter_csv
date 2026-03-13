# frozen_string_literal: true

require 'tempfile'

# SmarterCSV stores @input = the IO object passed in, not a path string.
# This means the Tempfile object is kept alive for the Reader's lifetime,
# preventing Ruby's GC from running the Tempfile finalizer (which calls unlink)
# while processing is in progress.
#
# The dangerous footgun this guards against:
#   temp = Tempfile.new('data')
#   temp.write(csv); temp.rewind
#   enumerator = SomeLib.process(temp.path)  # passes a String, not the object
#   temp = nil; GC.start                     # Tempfile finalizer runs → file unlinked
#   enumerator.next                          # Errno::ENOENT or silent truncation
#
# SmarterCSV avoids this by holding @input = tempfile (the object),
# so the reference chain caller → Reader → @input keeps the Tempfile alive.

describe 'Tempfile input safety' do
  let(:csv_content) { "name,age\nAlice,30\nBob,25\n" }

  def make_tempfile(content)
    t = Tempfile.new(['smarter_csv_test', '.csv'])
    t.write(content)
    t.rewind
    t
  end

  it 'holds a strong reference to the Tempfile on the Reader' do
    tempfile = make_tempfile(csv_content)
    reader = SmarterCSV::Reader.new(tempfile, {})
    expect(reader.input).to be(tempfile)
  end

  it 'processes a Tempfile correctly' do
    tempfile = make_tempfile(csv_content)
    result = SmarterCSV.process(tempfile)
    expect(result).to eq [{ name: 'Alice', age: 30 }, { name: 'Bob', age: 25 }]
  end

  it 'retains the Tempfile reference after the caller clears their local variable' do
    tempfile = make_tempfile(csv_content)
    reader = SmarterCSV::Reader.new(tempfile, {})
    original_path = tempfile.path

    # Simulate the caller dropping their only reference — Reader's @input is the only one left.
    # If Reader did NOT hold a strong reference, GC could finalize the Tempfile here,
    # calling unlink() and making the file disappear before reader.process runs.
    tempfile = nil
    GC.start
    GC.compact if GC.respond_to?(:compact)

    # File must still exist — Tempfile finalizer must not have run
    expect(File.exist?(original_path)).to be true

    # Reader must still process successfully
    result = reader.process
    expect(result.size).to eq 2
  ensure
    File.unlink(original_path) if original_path && File.exist?(original_path)
  end

  context 'with SmarterCSV.each (enumerator mode)' do
    it 'retains the Tempfile reference through the returned Enumerator' do
      # Enumerator → Reader → @input = Tempfile: the chain must stay intact
      # even after the call site that created the Tempfile has returned.
      tempfile = make_tempfile(csv_content)
      enumerator = SmarterCSV.each(tempfile)
      original_path = tempfile.path

      tempfile = nil
      GC.start
      GC.compact if GC.respond_to?(:compact)

      expect(File.exist?(original_path)).to be true
      results = enumerator.to_a
      expect(results.size).to eq 2
    ensure
      File.unlink(original_path) if original_path && File.exist?(original_path)
    end
  end
end
