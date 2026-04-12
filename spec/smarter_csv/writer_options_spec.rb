# frozen_string_literal: true

RSpec.describe SmarterCSV::Writer do
  let(:row_sep) { $/ }

  describe '.default_options' do
    it 'returns the DEFAULT_OPTIONS hash' do
      expect(SmarterCSV::Writer.default_options).to eq SmarterCSV::Writer::Options::DEFAULT_OPTIONS
    end
  end

  describe 'write_nil_value option' do
    context 'in direct-write mode (known headers)' do
      it 'replaces nil field values with the given string' do
        io = StringIO.new
        writer = SmarterCSV::Writer.new(io, headers: [:a, :b, :c], write_nil_value: 'N/A')
        writer << { a: 'foo', b: nil, c: 'bar' }
        writer.finalize
        io.rewind
        lines = io.string.split(row_sep)
        expect(lines[1]).to eq('foo,N/A,bar')
      end

      it 'defaults to empty string for nil values when no option given' do
        io = StringIO.new
        writer = SmarterCSV::Writer.new(io, headers: [:a, :b])
        writer << { a: 'foo', b: nil }
        writer.finalize
        io.rewind
        lines = io.string.split(row_sep)
        expect(lines[1]).to eq('foo,')
      end
    end

    context 'in discovery mode' do
      it 'replaces nil field values with the given string' do
        io = StringIO.new
        writer = SmarterCSV::Writer.new(io, write_nil_value: 'N/A')
        writer << { a: 'foo', b: nil, c: 'bar' }
        writer.finalize
        io.rewind
        lines = io.string.split(row_sep)
        expect(lines[1]).to eq('foo,N/A,bar')
      end
    end
  end

  describe 'write_empty_value option' do
    context 'in direct-write mode (known headers)' do
      it 'replaces empty string field values with the given string' do
        io = StringIO.new
        writer = SmarterCSV::Writer.new(io, headers: [:a, :b, :c], write_empty_value: 'EMPTY')
        writer << { a: 'foo', b: '', c: 'bar' }
        writer.finalize
        io.rewind
        lines = io.string.split(row_sep)
        expect(lines[1]).to eq('foo,EMPTY,bar')
      end

      it 'does not affect nil values (write_nil_value handles those)' do
        io = StringIO.new
        writer = SmarterCSV::Writer.new(io, headers: [:a, :b], write_nil_value: 'NIL', write_empty_value: 'EMPTY')
        writer << { a: nil, b: '' }
        writer.finalize
        io.rewind
        lines = io.string.split(row_sep)
        expect(lines[1]).to eq('NIL,EMPTY')
      end

      it 'applies write_empty_value to missing keys (which default to empty string)' do
        io = StringIO.new
        # headers has :c but the row does not — missing key defaults to '' which should be substituted
        writer = SmarterCSV::Writer.new(io, headers: [:a, :b, :c], write_empty_value: 'MISSING')
        writer << { a: 'foo', b: 'bar' }
        writer.finalize
        io.rewind
        lines = io.string.split(row_sep)
        expect(lines[1]).to eq('foo,bar,MISSING')
      end
    end

    context 'in discovery mode' do
      it 'replaces empty string field values with the given string' do
        io = StringIO.new
        writer = SmarterCSV::Writer.new(io, write_empty_value: 'EMPTY')
        writer << { a: 'foo', b: '', c: 'bar' }
        writer.finalize
        io.rewind
        lines = io.string.split(row_sep)
        expect(lines[1]).to eq('foo,EMPTY,bar')
      end
    end
  end

  describe 'encoding option' do
    let(:tmp_path) { '/tmp/test_encoding_output.csv' }

    after(:each) { File.delete(tmp_path) if File.exist?(tmp_path) }

    it 'opens the output file with the specified encoding' do
      writer = SmarterCSV::Writer.new(tmp_path, headers: [:name], encoding: 'UTF-8')
      writer << { name: 'Ångström' }
      writer.finalize
      # File should be readable back as UTF-8 without errors
      content = File.read(tmp_path, encoding: 'UTF-8')
      expect(content).to include('Ångström')
    end

    it 'writes ISO-8859-1 encoded content when encoding is set' do
      writer = SmarterCSV::Writer.new(tmp_path, headers: [:name], encoding: 'ISO-8859-1')
      writer << { name: 'caf'.encode('ISO-8859-1') }
      writer.finalize
      raw = File.binread(tmp_path)
      # header line 'name' is pure ASCII, data row contains 'caf'
      expect(raw).to include('name')
      expect(raw).to include('caf')
    end

    it 'uses system default encoding when encoding option is not given' do
      writer = SmarterCSV::Writer.new(tmp_path, headers: [:a])
      writer << { a: 'test' }
      writer.finalize
      expect(File.exist?(tmp_path)).to be true
      expect(File.read(tmp_path)).to include('test')
    end
  end

  describe 'write_bom option' do
    let(:bom) { "\xEF\xBB\xBF" }

    it 'prepends a UTF-8 BOM in discovery mode' do
      io = StringIO.new
      writer = SmarterCSV::Writer.new(io, write_bom: true)
      writer << { name: 'Ångström', value: 42 }
      writer.finalize
      io.rewind
      raw = io.string
      expect(raw).to start_with(bom)
      lines = raw.sub(bom, '').split(row_sep)
      expect(lines[0]).to eq('name,value')
      expect(lines[1]).to eq('Ångström,42')
    end

    it 'prepends a UTF-8 BOM in direct-write mode (known headers)' do
      io = StringIO.new
      writer = SmarterCSV::Writer.new(io, headers: [:name, :value], write_bom: true)
      writer << { name: 'Ångström', value: 42 }
      writer.finalize
      io.rewind
      raw = io.string
      expect(raw).to start_with(bom)
      lines = raw.sub(bom, '').split(row_sep)
      expect(lines[0]).to eq('name,value')
      expect(lines[1]).to eq('Ångström,42')
    end

    it 'writes the BOM exactly once (not duplicated)' do
      io = StringIO.new
      writer = SmarterCSV::Writer.new(io, write_bom: true)
      writer << { x: 1 }
      writer.finalize
      io.rewind
      raw = io.string
      expect(raw.scan(bom).length).to eq(1)
    end

    it 'does not prepend a BOM when write_bom is false (default)' do
      io = StringIO.new
      writer = SmarterCSV::Writer.new(io, headers: [:name])
      writer << { name: 'test' }
      writer.finalize
      io.rewind
      expect(io.string).not_to start_with("\xEF\xBB\xBF")
    end
  end

  describe 'write_headers option' do
    context 'default behavior (write_headers: true)' do
      it 'emits header line in header-discovery mode' do
        io = StringIO.new
        writer = SmarterCSV::Writer.new(io)
        writer << { name: 'Alice', age: 30 }
        writer.finalize
        io.rewind
        lines = io.string.split(row_sep)
        expect(lines[0]).to eq('name,age')
        expect(lines[1]).to eq('Alice,30')
      end

      it 'emits header line in direct-write mode (headers: given)' do
        io = StringIO.new
        writer = SmarterCSV::Writer.new(io, headers: %i[name age])
        writer << { name: 'Alice', age: 30 }
        writer.finalize
        io.rewind
        lines = io.string.split(row_sep)
        expect(lines[0]).to eq('name,age')
        expect(lines[1]).to eq('Alice,30')
      end
    end

    context 'write_headers: false' do
      it 'omits the header line in header-discovery mode' do
        io = StringIO.new
        writer = SmarterCSV::Writer.new(io, write_headers: false)
        writer << { name: 'Alice', age: 30 }
        writer.finalize
        io.rewind
        lines = io.string.split(row_sep)
        expect(lines.length).to eq(1)
        expect(lines[0]).to eq('Alice,30')
      end

      it 'omits the header line in direct-write mode (headers: given)' do
        io = StringIO.new
        writer = SmarterCSV::Writer.new(io, headers: %i[name age], write_headers: false)
        writer << { name: 'Alice', age: 30 }
        writer.finalize
        io.rewind
        lines = io.string.split(row_sep)
        expect(lines.length).to eq(1)
        expect(lines[0]).to eq('Alice,30')
      end

      it 'appends data rows only to an existing CSV (simulate append mode)' do
        # First write: create file with header
        io = StringIO.new
        writer = SmarterCSV::Writer.new(io)
        writer << { name: 'Alice', age: 30 }
        writer.finalize
        io.rewind
        existing_content = io.string

        # Second write: append rows only
        append_io = StringIO.new
        writer2 = SmarterCSV::Writer.new(append_io, write_headers: false)
        writer2 << { name: 'Bob', age: 25 }
        writer2.finalize
        append_io.rewind

        combined = existing_content + append_io.string
        lines = combined.split(row_sep)
        expect(lines[0]).to eq('name,age')
        expect(lines[1]).to eq('Alice,30')
        expect(lines[2]).to eq('Bob,25')
      end

      it 'still respects column ordering from map_headers when write_headers: false' do
        io = StringIO.new
        writer = SmarterCSV::Writer.new(io, map_headers: { name: 'Name', age: 'Age' }, write_headers: false)
        writer << { name: 'Alice', age: 30 }
        writer.finalize
        io.rewind
        lines = io.string.split(row_sep)
        expect(lines.length).to eq(1)
        expect(lines[0]).to eq('Alice,30')
      end

      it 'works through SmarterCSV.generate with write_headers: false' do
        result = SmarterCSV.generate(write_headers: false) do |csv|
          csv << { name: 'Alice', age: 30 }
          csv << { name: 'Bob',   age: 25 }
        end
        lines = result.split(row_sep)
        expect(lines.length).to eq(2)
        expect(lines[0]).to eq('Alice,30')
        expect(lines[1]).to eq('Bob,25')
      end

      it 'appends data rows only when the IO is opened in append mode' do
        path = '/tmp/test_write_headers_append.csv'
        begin
          # First write: create the file with header + first row
          SmarterCSV.generate(path) do |csv|
            csv << { name: 'Alice', age: 30 }
          end

          # Second write: open in 'a' mode and suppress the header
          File.open(path, 'a') do |f|
            SmarterCSV.generate(f, write_headers: false) do |csv|
              csv << { name: 'Bob', age: 25 }
            end
          end

          lines = File.read(path).split(row_sep)
          expect(lines.length).to eq(3)
          expect(lines[0]).to eq('name,age')
          expect(lines[1]).to eq('Alice,30')
          expect(lines[2]).to eq('Bob,25')
        ensure
          File.delete(path) if File.exist?(path)
        end
      end
    end
  end
end
