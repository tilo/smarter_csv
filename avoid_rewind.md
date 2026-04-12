# Avoid Rewind: PeekableIO Wrapper

## The Problem

`SmarterCSV::Reader#process` currently calls two auto-detection methods before reading data:

```ruby
# lib/smarter_csv/reader.rb
options[:row_sep] = guess_line_ending(fh, options)        if options[:row_sep]&.to_sym == :auto
options[:col_sep] = guess_column_separator(fh, options)   if options[:col_sep]&.to_sym == :auto
```

Both methods in `auto_detection.rb` read from the IO object and then call `rewind`:

```ruby
def guess_line_ending(filehandle, options)
  filehandle.each_char { ... }
  rewind(filehandle)          # <-- BREAKS pipes, stdin, network streams, Zlib, etc.
end

def guess_column_separator(filehandle, options)
  count.times { next_line_with_counts(filehandle, options) }
  rewind(filehandle)          # <-- same problem
end
```

`rewind` calls `filehandle.rewind`, which only works on seekable IO objects:
- `File` — seekable ✅
- `StringIO` — seekable ✅
- `IO.pipe` — **not seekable** ❌
- `STDIN` — **not seekable** ❌
- `Zlib::GzipReader` — **not seekable** ❌
- `Net::HTTP` response body — **not seekable** ❌
- Any custom streaming IO — **likely not seekable** ❌

Today, passing a pipe or stream with `:row_sep: :auto` or `:col_sep: :auto` silently
fails or raises a cryptic `Errno::ESPIPE` error. This is a user-facing bug.

## Why a PeekableIO Wrapper Is the Right Fix

The insight is simple: **we don't need to rewind if we never discard the bytes we already read.**

Instead of seeking back to the start, we read a small peek chunk *once* at the beginning,
perform auto-detection on that in-memory string, and then arrange for those same bytes to be
re-read as part of normal processing — as if the IO had been rewound.

This works for **any** IO source because:
- It only ever calls `.read(n)` on the underlying IO (forward-only, universally supported)
- `rewind` on the wrapper simply resets the read position back to the start of the
  in-memory buffer — it never touches the underlying IO at all
- The buffer **is** the rewind. Since auto-detection happens at the very start of
  processing, the buffer always covers byte 0 of the source
- Ruby's `read(n)` returns a correctly-encoded String, so encoding and multi-byte
  character boundaries are handled by Ruby — no byte-level assembly needed,
  no encoding-specific C code required

## What We Need to Achieve

1. **Auto-detection works on all IO sources**, including non-seekable ones (pipes, stdin,
   gzip streams, network sockets, custom streaming objects).
2. **No data is lost.** The bytes read during auto-detection are replayed to the parser
   as if they were never consumed.
3. **Seekable sources continue to work identically.** Files and StringIO are unaffected
   in behavior; they just go through the wrapper transparently.
4. **Encoding is fully preserved.** The wrapper must propagate `external_encoding` from
   the underlying IO so the rest of the pipeline sees the correct encoding.
5. **The change is minimal and self-contained.** `auto_detection.rb`, `file_io.rb`,
   and `reader.rb` should require little or no changes — the wrapper is a drop-in IO.

## Implementation Plan

### Step 1 — Create `lib/smarter_csv/peekable_io.rb`

```ruby
# frozen_string_literal: true

module SmarterCSV
  # PeekableIO wraps any IO-like object and allows a peek buffer to be pre-filled
  # (e.g. for auto-detection) without requiring the underlying source to be seekable.
  #
  # After the peek buffer is drained, all reads delegate directly to the wrapped IO.
  # This makes it a transparent, forward-only wrapper compatible with pipes, stdin,
  # gzip streams, and any other non-seekable source.
  #
  # Usage:
  #   pio = PeekableIO.new(io)
  #   peek_str = pio.peek(8192)   # reads up to 8192 bytes, buffers them
  #   # ... perform auto-detection on peek_str ...
  #   # now use pio as a normal IO — peek bytes are replayed first
  #
  class PeekableIO
    # How many bytes to read for auto-detection when the source is non-seekable.
    DEFAULT_PEEK_SIZE = 16_384  # 16KB — enough for separator detection on any real CSV

    def initialize(io)
      @io = io
      @peek_buf = nil  # nil means bootstrap phase not yet started
      @peek_pos = 0
    end

    # Read up to `n` bytes into the peek buffer and return them as a String.
    # The peeked bytes will be replayed on subsequent reads (gets, readline, read, each_char).
    # Called once at the start of processing, before auto-detection.
    def peek(n = DEFAULT_PEEK_SIZE)
      chunk = @io.read(n)
      if chunk && !chunk.empty?
        @peek_buf = chunk.b  # store as raw bytes; encoding applied on read-out
        @peek_pos = 0
      end
      chunk
    end

    # Hot path: once buffer is drained (@peek_buf is nil), delegates directly to
    # underlying IO with a single nil check — zero overhead for large files.
    def gets(sep = $/, **kwargs)
      return @io.gets(sep, **kwargs) if @peek_buf.nil?

      rest = @peek_buf.byteslice(@peek_pos..)
      rest.force_encoding(external_encoding || Encoding::UTF_8)
      idx = rest.index(sep)
      if idx
        line = rest[0, idx + sep.bytesize]
        @peek_pos += line.bytesize
        @peek_buf = nil if @peek_pos >= @peek_buf.bytesize  # drain → release memory
        return line
      else
        @peek_buf = nil  # drain → release memory
        remainder = @io.gets(sep, **kwargs)
        return remainder ? rest + remainder : rest
      end
    end

    alias readline gets

    def read(n = nil)
      return @io.read(n) if @peek_buf.nil?

      buffered = @peek_buf.byteslice(@peek_pos..)
      buffered.force_encoding(external_encoding || Encoding::BINARY)
      @peek_buf = nil  # drain → release memory
      return n ? buffered[0, n] : buffered + (@io.read || '')
    end

    def each_char
      return enum_for(:each_char) unless block_given?
      return @io.each_char { |c| yield c } if @peek_buf.nil?

      rest = @peek_buf.byteslice(@peek_pos..)
      rest.force_encoding(external_encoding || Encoding::UTF_8)
      rest.each_char { |c| yield c }
      @peek_buf = nil  # drain → release memory
      @io.each_char { |c| yield c }
    end

    def eof?
      return @io.eof? if @peek_buf.nil?

      @io.eof?  # peek_buf still has data, but underlying IO may also not be EOF
    end

    def rewind
      # Reset to the start of the peek buffer — never touches the underlying IO.
      # Since auto-detection always happens at the very beginning, the buffer IS byte 0.
      # Works identically for files, StringIO, pipes, and any other source.
      @peek_pos = 0
    end

    def close
      @io.close if @io.respond_to?(:close)
    end

    def external_encoding
      @io.respond_to?(:external_encoding) ? @io.external_encoding : nil
    end

    def respond_to_missing?(method, include_private = false)
      @io.respond_to?(method, include_private) || super
    end

    def method_missing(method, *args, **kwargs, &block)
      @io.send(method, *args, **kwargs, &block)
    end
  end
end
```

### Step 2 — `auto_detection.rb` — no changes needed

The `rewind(filehandle)` calls stay exactly as they are. They now call `PeekableIO#rewind`,
which just resets `@peek_pos = 0`. The bytes are replayed on the next read.
`auto_detection.rb` is completely unaware that anything changed.

### Step 3 — Wrap the IO in `reader.rb#process`

One line becomes two:

```ruby
# BEFORE (reader.rb ~114):
fh = input.respond_to?(:readline) ? input : File.open(input, "r:#{options[:file_encoding]}")

# AFTER:
fh = input.respond_to?(:readline) ? input : File.open(input, "r:#{options[:file_encoding]}")
fh = SmarterCSV::PeekableIO.new(fh)
```

Always wrap — no conditional needed. For seekable sources the wrapper is transparent
(rewind just resets peek_pos, which happens to cover byte 0 since we start there).
For non-seekable sources it works correctly without any special-casing.

### Step 4 — Require the new file

```ruby
# lib/smarter_csv.rb
require_relative 'smarter_csv/peekable_io'
```

---

## Tests Required

These are the scenarios that break today and must pass after the fix.

### 1. Pipe source with `:row_sep: :auto`

```ruby
describe 'PeekableIO with non-seekable sources' do
  it 'auto-detects row_sep on a pipe without raising Errno::ESPIPE' do
    csv_content = "name,age\nAlice,30\nBob,25\n"
    reader_io, writer_io = IO.pipe
    writer_io.write(csv_content)
    writer_io.close

    result = SmarterCSV.process(reader_io, row_sep: :auto, col_sep: ',')
    expect(result).to eq([{ name: 'Alice', age: '30' }, { name: 'Bob', age: '25' }])
  ensure
    reader_io.close unless reader_io.closed?
  end
end
```

### 2. Pipe source with `:col_sep: :auto`

```ruby
it 'auto-detects col_sep on a pipe without raising Errno::ESPIPE' do
  csv_content = "name;age\nAlice;30\nBob;25\n"
  reader_io, writer_io = IO.pipe
  writer_io.write(csv_content)
  writer_io.close

  result = SmarterCSV.process(reader_io, row_sep: "\n", col_sep: :auto)
  expect(result).to eq([{ name: 'Alice', age: '30' }, { name: 'Bob', age: '25' }])
ensure
  reader_io.close unless reader_io.closed?
end
```

### 3. Pipe source with both `:row_sep: :auto` and `:col_sep: :auto`

```ruby
it 'auto-detects both separators on a pipe' do
  csv_content = "name\tage\r\nAlice\t30\r\nBob\t25\r\n"
  reader_io, writer_io = IO.pipe
  writer_io.write(csv_content)
  writer_io.close

  result = SmarterCSV.process(reader_io, row_sep: :auto, col_sep: :auto)
  expect(result).to eq([{ name: 'Alice', age: '30' }, { name: 'Bob', age: '25' }])
ensure
  reader_io.close unless reader_io.closed?
end
```

### 4. STDIN-like source (simulated with a non-seekable StringIO subclass)

```ruby
class NonSeekableIO
  def initialize(str)
    @io = StringIO.new(str)
  end
  def read(n = nil) = @io.read(n)
  def gets(sep = $/) = @io.gets(sep)
  def readline(sep = $/) = @io.readline(sep)
  def each_char(&block) = @io.each_char(&block)
  def eof? = @io.eof?
  def external_encoding = Encoding::UTF_8
  def close = nil
  # Intentionally does NOT implement rewind or seek
end

it 'works with a non-seekable IO that has no rewind method' do
  io = NonSeekableIO.new("a,b\n1,2\n3,4\n")
  result = SmarterCSV.process(io, row_sep: :auto, col_sep: :auto)
  expect(result).to eq([{ a: '1', b: '2' }, { a: '3', b: '4' }])
end
```

### 5. PeekableIO unit tests

```ruby
describe SmarterCSV::PeekableIO do
  let(:content) { "header1,header2\nval1,val2\n" }
  let(:io) { StringIO.new(content) }
  subject(:pio) { described_class.new(io) }

  describe '#peek' do
    it 'returns the peeked content' do
      expect(pio.peek(10)).to eq(content[0, 10])
    end

    it 'does not lose data on subsequent gets' do
      pio.peek(16_384)
      expect(pio.gets("\n")).to eq("header1,header2\n")
      expect(pio.gets("\n")).to eq("val1,val2\n")
    end
  end

  describe '#gets' do
    it 'replays peeked bytes before reading from underlying IO' do
      pio.peek(7)  # "header1"
      expect(pio.gets("\n")).to eq("header1,header2\n")
    end
  end

  describe '#each_char' do
    it 'replays peeked bytes then continues from underlying IO' do
      pio.peek(4)
      chars = []
      pio.each_char { |c| chars << c }
      expect(chars.join).to eq(content)
    end
  end

  describe '#eof?' do
    it 'is false while peek buffer has unread bytes' do
      pio.peek(16_384)
      expect(pio.eof?).to be false
    end

    it 'is true after all content consumed' do
      pio.peek(16_384)
      pio.read
      expect(pio.eof?).to be true
    end
  end

  describe 'buffer lifecycle' do
    it 'peek_buf is nil before peek is called' do
      expect(pio.instance_variable_get(:@peek_buf)).to be_nil
    end

    it 'peek_buf is set after peek' do
      pio.peek(16_384)
      expect(pio.instance_variable_get(:@peek_buf)).not_to be_nil
    end

    it 'peek_buf is nil (released) after buffer is fully drained' do
      pio.peek(16_384)
      pio.read  # drains everything
      expect(pio.instance_variable_get(:@peek_buf)).to be_nil
    end
  end

  describe '#external_encoding' do
    it 'delegates to the underlying IO' do
      io = StringIO.new(content)
      io.set_encoding(Encoding::ISO_8859_1)
      pio = described_class.new(io)
      expect(pio.external_encoding).to eq(Encoding::ISO_8859_1)
    end
  end
end
```

### 6. Regression: existing file-based tests must still pass

No new tests needed here — the full existing test suite is the regression guard.
Run `bundle exec rake spec` and verify it stays green.

---

## What NOT to Do

- **Do not branch on seekability anywhere.** The whole point is one code path that
  works everywhere. No `respond_to?(:rewind)` checks, no `is_seekable?` flags.
- **Do not use an empty string `''.b` as the "no buffer" sentinel.** Use `nil`.
  `@peek_buf.nil?` is the fast-path guard at the top of every method — a single pointer
  comparison. Once nil, the 16KB buffer is eligible for GC immediately. An empty string
  would still allocate an object and require a `bytesize == 0` check instead.
- **Do not do encoding handling in PeekableIO.** Store bytes as binary (`''.b`),
  re-apply encoding when emitting strings (force_encoding from the underlying IO).
  Encoding is Ruby's job, not the buffer's job.
- **Do not build a C extension for this.** Ruby's `read(n)` already calls into C
  internally. A Ruby wrapper is fast enough and keeps encoding handling correct for free.
- **Do not replace the auto_detection logic.** `guess_line_ending` and
  `guess_column_separator` are correct — they just need the rewind to become a no-op.

---

## Version Impact

Since this fixes a silent bug for non-seekable IO sources (a behavioral change for a
previously broken edge case), it qualifies as a **minor version bump**: `1.17.0`.

It would only be a major version (`2.0.0`) if the public API changed or existing
working behavior changed — neither is the case here.
