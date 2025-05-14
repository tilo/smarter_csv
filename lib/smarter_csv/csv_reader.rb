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
      @max_sep_length = [
        @col_sep.size,
        @row_sep.size,
        @double_quote_char.size
      ].max
    end

    # ---------------------------------------------------------------
    # Finite State Machine to read CSV row as fields
    def read_row_as_fields
      @fields = []
      row_complete = false

      until row_complete
        sep = peek_chars(@max_sep_length)

        field, field_closed = read_field
        raise SmarterCSV::MalformedCSV, "Unclosed quoted field" unless field_closed

        @fields << field unless field.nil?

        sep = peek_chars(@max_sep_length)

        if sep&.start_with?(@col_sep)
          skip_chars(@col_sep.size)
        elsif sep&.start_with?(@row_sep)
          skip_chars(@row_sep.size)
          row_complete = true
        elsif sep.nil? || sep.empty?
          row_complete = true
        else
          raise SmarterCSV::MalformedCSV, "Expected separator but found: #{sep.inspect}"
        end
      end

      @fields.empty? ? nil : @fields
    end

    def read_field
      buffer = +""
      field_started = true
      field_ends_in_quote = false
      field_closed = false

      loop do
        peek = peek_chars(@max_sep_length)

        if field_started
          field_ends_in_quote = peek&.start_with?(@quote_char)
          skip_chars(@quote_char.size) if field_ends_in_quote
          field_started = false
          next
        end

        if peek.nil?
          # EOF while reading
          field_closed = !field_ends_in_quote
          break unless field_ends_in_quote

          return [nil, false] # unterminated quoted field
        end

        if field_ends_in_quote
          if peek.start_with?(@double_quote_char)
            skip_chars(@double_quote_char.size)
            buffer << @quote_char
          # elsif peek.start_with?(@quote_char)
          elsif peek.start_with?(@quote_char) && !peek.start_with?(@double_quote_char)
            skip_chars(@quote_char.size)
            field_closed = true
            break
          else
            ch = next_char
            buffer << ch if ch
          end
        else # unquoted field
          if peek.start_with?(@double_quote_char)
            skip_chars(@double_quote_char.size)
            buffer << @quote_char
          elsif peek.nil? || peek.start_with?(@col_sep) || peek.start_with?(@row_sep)
            field_closed = true
            break
          else
            ch = next_char
            buffer << ch if ch
          end
        end
      end

      [buffer, field_closed]
    end

    # ---------------------------------------------------------------
    # - row_sep might be cut in half

    def read_row
      row = +""
      @match_buffer = +""

      while (char = next_char)
        @match_buffer << char

        if @match_buffer == @row_sep
          row << @match_buffer
          return row
        elsif !@row_sep.start_with?(@match_buffer)
          row << @match_buffer.slice!(0)

          until @match_buffer.empty?
            if @match_buffer == @row_sep
              row << @match_buffer
              return row
            elsif @row_sep.start_with?(@match_buffer)
              break
            else
              row << @match_buffer.slice!(0)
            end
          end
        else
        end
      end

      row << @match_buffer unless @match_buffer.empty?
      row.empty? ? nil : row
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
      nil # Or raise Encoding::InvalidByteSequenceError, depending on your needs
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

    # fetch n characters from the io buffer
    def next_chars(n)
      n.times do
        ch = next_char
      end
    end
    alias skip_chars next_chars

    # it should be safe to assume in average a char is less than 16 bytes
    # def peek_chars(n)
    #   bytes = @io.peek_bytes(n * 16)
    #   return nil if bytes.nil? || bytes.empty?
    #
    #   str = bytes.dup.force_encoding(@encoding)
    #
    #   if str.valid_encoding?
    #     char_array = str.chars
    #     result = char_array[0, n].join
    #     return result
    #   end
    #
    #   nil
    # end

    # - it should be safe to assume in average a char is less than 16 bytes
    # - peek_bytes may contain invalid sequences if a multi-byte character is cut
    def peek_chars(n)
      bytes = @io.peek_bytes(n * 16)
      return nil if bytes.nil? || bytes.empty?

      str = bytes.dup.force_encoding(@encoding)

      if str.valid_encoding?
        result = str.chars.first(n).join
        return result
      else
        # this fixes the issue with partially cut multi-byte characters
        valid_prefix = bytes.byteslice(0, bytes.length)
                            .force_encoding(@encoding)
                            .scrub('')
                            .chars
                            .first(n)
                            .join
        return valid_prefix unless valid_prefix.empty?
      end

      nil
    end
    # rubocop:enable Naming/MethodParameterName
  end
end
