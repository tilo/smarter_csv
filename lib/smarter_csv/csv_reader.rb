# frozen_string_literal: true

module SmarterCSV
  class CSVReader
    attr_reader :io, :encoding, :buffer_size
    attr_reader :quote_char, :double_quote_char, :col_sep, :row_sep

    def initialize(source, options)
      @buffer_size = options[:buffer_size] || (128 * 1024)
      @io = SmarterCSV::BufferedIO.new(source, @buffer_size)
      @encoding = source.respond_to?(:external_encoding) ? source.external_encoding : Encoding::UTF_8
      @row_sep = options[:row_sep]
      @col_sep = options[:col_sep]
      @quote_char = options[:quote_char]
      @double_quote_char = options[:quote_char] * 2

      @max_sep_length  = [@col_sep.size, @row_sep.size, 2].max
    end

    # ---------------------------------------------------------------
    # Finite State Machine to read CSV row as fields
    def read_row_as_fields
      @fields = []
      @buffer = +""
      state = :start_field
      in_quotes = false
      quote_balanced = false

      loop do
        peek = peek_chars(@max_sep_length)

        # --- End of File ---
        if peek.nil?
          # if we were inside a quoted field and it's not closed, it's an error
          if in_quotes || !quote_balanced
            raise SmarterCSV::MalformedCSVError, "Unclosed quoted field"
          end
          finalize_field
          return @fields.empty? ? nil : @fields
        end

        # Handle quoted field
        if state == :start_field
          if peek.start_with?(@quote_char)
            in_quotes = true
            quote_balanced = false
            skip_chars(@quote_char.size)
            state = :in_field
            next
          else
            in_quotes = false
            quote_balanced = true
            state = :in_field
          end
        end

        if in_quotes
          # Check for escaped quote or closing quote
          if peek.start_with?(@double_quote_char)
            skip_chars(@double_quote_char.size)
            @buffer << @quote_char
          elsif peek.start_with?(@quote_char)
            skip_chars(@quote_char.size)
            in_quotes = false
            quote_balanced = true
          else
            ch = next_char
            @buffer << ch if ch
          end
        else
          # Check field and row separators
          if peek.start_with?(@col_sep)
            skip_chars(@col_sep.size)
            finalize_field
            state = :start_field
          elsif peek.start_with?(@row_sep)
            skip_chars(@row_sep.size)
            finalize_field
            return @fields
          else
            ch = next_char
            @buffer << ch if ch
          end
        end
      end
    end

    def finalize_field
      # remove surrounding quotes if needed, already handled
      @fields << @buffer.dup
      @buffer.clear
    end

    # ---------------------------------------------------------------

    def read_row
      row = +""
      @match_buffer = +""

      while (char = next_char)
        @match_buffer << char

        if @match_buffer == @row_sep
          row << @match_buffer
          return row
        end

        next if @row_sep.start_with?(@match_buffer)

        row << @match_buffer[0]
        @match_buffer = @match_buffer[1..-1] || +""
      end

      row << @match_buffer unless @match_buffer.empty?
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

    def peek_chars(n)
      chars = []
      offset = 1

      while chars.size < n
        bytes = @io.peek_bytes(offset)
        break if bytes.nil? || bytes.empty?

        str = bytes.dup.force_encoding(@encoding)

        if str.valid_encoding?
          char_array = str.chars
          return char_array[0, n].join if char_array.size >= n
        end

        break if bytes.bytesize >= 128  # safety limit
        offset += 1
      end

      nil
    end

    def peek_char
      n = 1
      loop do
        bytes = @io.peek_bytes(n)
        return nil if bytes.nil? || bytes.bytesize == 0

        str = bytes.dup.force_encoding(@encoding)
        return str if str.valid_encoding?

        break if bytes.bytesize >= 64

        n += 1
      end
      nil
    end

    def next_char
      bytes = +""
      while (b = @io.next_byte)
        bytes << b if b
        str = bytes.dup.force_encoding(@encoding)
        return str if str.valid_encoding?

        break if bytes.bytesize >= 64 || b.nil? # too many bytes or EOF
      end
      nil  # Or raise Encoding::InvalidByteSequenceError, depending on your needs
    end

    # fetch n characters from the io buffer
    def next_chars(n)
      n.times { next_char }
    end
    alias_method :skip_chars, :next_chars
  end
end
