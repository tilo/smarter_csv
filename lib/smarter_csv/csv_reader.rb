# frozen_string_literal: true

module SmarterCSV
  class CSVReader
    def initialize(buffered_io, options, encoding = Encoding::UTF_8)
      @io = buffered_io
      @encoding = encoding
      @row_sep = options[:row_sep]
      @col_sep = options[:col_sep]
      @quote_char = options[:quote_char]
    end

    def read_row_as_fields(col_sep: ',', quote_char: '"')
      fields = []
      field = ""
      state = :start_field

      loop do
        char = next_char
        break if char.nil?

        case state
        when :start_field
          if char == quote_char
            state = :in_quoted_field
          elsif char == col_sep
            fields << ""
          elsif row_separator?(char)
            fields << ""
            break
          else
            field << char
            state = :in_field
          end

        when :in_field
          if char == col_sep
            fields << field
            field = ""
            state = :start_field
          elsif row_separator?(char)
            fields << field
            break
          else
            field << char
          end

        when :in_quoted_field
          if char == quote_char
            state = :quote_terminated
          else
            field << char
          end

        when :quote_terminated
          if char == quote_char
            field << quote_char
            state = :in_quoted_field
          elsif char == col_sep
            fields << field
            field = ""
            state = :start_field
          elsif row_separator?(char)
            fields << field
            break
          else
            field << char
            state = :in_field
          end
        end
      end

      fields.empty? ? nil : fields
    end

    def read_row
      row = +""
      while (char = next_char)
        row << char
        break if row_separator?(char)
      end
      row.empty? ? nil : row
    end

    # rubocop:disable Naming/MethodParameterName
    def read_rows(n)
      rows = []
      n.times do
        row = read_row
        break if row.nil?

        rows << row
      end
      rows
    end
    # rubocop:enable Naming/MethodParameterName

    def next_char
      bytes = +""
      while (b = @io.peek_byte)
        bytes << b
        len = bytes.bytesize

        clen = char_length(bytes)
        break if clen == len
        break if clen == -1 || len >= 4

        @io.next_byte # consume if still assembling
      end

      return nil if bytes.empty?

      # consume what we peeked
      bytes.bytesize.times { @io.next_byte }
      bytes.force_encoding(@encoding)
    end
    
    private

    def char_length(bytes)
      ptr = bytes.bytes
      rb_enc_precise_mbclen(ptr.pack("C*"), ptr.pack("C*") + bytes.bytesize, @encoding)
    rescue StandardError
      -1
    end

    def row_separator?(char)
      char == "\n"
    end
  end
end
