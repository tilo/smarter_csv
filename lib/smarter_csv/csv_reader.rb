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
        puts "---- #{@max_sep_length}"
        sep = peek_chars(@max_sep_length)
        puts "[read_row_as_fields] top-of-loop peek: #{sep.inspect}"

        field, field_closed = read_field
        raise SmarterCSV::MalformedCSV, "Unclosed quoted field" unless field_closed

        @fields << field unless field.nil?

        sep = peek_chars(@max_sep_length)
        puts "[read_row_as_fields] post-field peek: #{sep.inspect}"

        if sep&.start_with?(@col_sep)
          skip_chars(@col_sep.size)
          puts "[read_row_as_fields] skipped col_sep"
        elsif sep&.start_with?(@row_sep)
          skip_chars(@row_sep.size)
          puts "[read_row_as_fields] skipped row_sep"
          row_complete = true
        elsif sep.nil? || sep.empty?
          puts "[read_row_as_fields] EOF or empty after field"
          row_complete = true
        else
          raise SmarterCSV::MalformedCSV, "Expected separator but found: #{sep.inspect}"
        end
      end

      puts "Fields: #{@fields.inspect}"
      @fields.empty? ? nil : @fields
    end

    def read_field
      puts '[read_field] start of method'
      buffer = +""
      field_started = true
      field_ends_in_quote = false
      field_closed = false

      loop do
        puts "----#{@max_sep_length}"
        peek = peek_chars(@max_sep_length)
        puts "[read_field] top-of-loop peek: #{peek.inspect}"

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

        puts "[read_field] peek: #{peek.inspect}"
        if field_ends_in_quote
          if peek.start_with?(@double_quote_char)
            puts "[read_field] matched double_quote_char: #{peek[0, @double_quote_char.size].inspect}"
            skip_chars(@double_quote_char.size)
            puts "[read_field] after skip #{@double_quote_char}, next peek: #{peek_chars(@max_sep_length).inspect}"
            buffer << @quote_char
          # elsif peek.start_with?(@quote_char)
          elsif peek.start_with?(@quote_char) && !peek.start_with?(@double_quote_char)
            puts "[read_field] matched closing quote"
            skip_chars(@quote_char.size)
            field_closed = true
            break
          else
            ch = next_char
            puts "[read_field] quoted field: consumed #{ch}"
            buffer << ch if ch
            puts "[read_field] buffer: #{buffer.inspect}"
          end
        else # unquoted field
          if peek.start_with?(@double_quote_char)
            puts "[read_field] matched double_quote_char: #{peek[0, @double_quote_char.size].inspect}"
            skip_chars(@double_quote_char.size)
            puts "[read_field] after skip #{@double_quote_char}, next peek: #{peek_chars(@max_sep_length).inspect}"
            buffer << @quote_char
          elsif peek.nil? || peek.start_with?(@col_sep) || peek.start_with?(@row_sep)
            field_closed = true
            break
          else
            ch = next_char
            puts "[read_field] un-quoted field: consumed #{ch}"
            buffer << ch if ch
            puts "[read_field] buffer: #{buffer.inspect}"
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
        puts "[read_row] char=#{char.inspect}, match_buffer=#{@match_buffer.inspect}"

        if @match_buffer == @row_sep
          row << @match_buffer
          puts "[read_row] matched full row_sep: #{@match_buffer.inspect}, returning row: #{row.inspect}"
          return row
        elsif !@row_sep.start_with?(@match_buffer)
          puts "[read_row] no prefix match: match_buffer=#{@match_buffer.inspect}, row_sep=#{@row_sep.inspect}"
          row << @match_buffer.slice!(0)

          until @match_buffer.empty?
            puts "[read_row] nested loop: match_buffer=#{@match_buffer.inspect}"
            if @match_buffer == @row_sep
              row << @match_buffer
              puts "[read_row] matched full row_sep: #{@match_buffer.inspect}, returning row: #{row.inspect}"
              return row
            elsif @row_sep.start_with?(@match_buffer)
              puts "[read_row] prefix match (nested): #{@match_buffer.inspect}"
              break
            else
              row << @match_buffer.slice!(0)
            end
          end
        else
          puts "[read_row] prefix match: #{@match_buffer.inspect}"
        end
      end

      puts "[read_row] fallback return: row=#{row.inspect}, buffer=#{@match_buffer.inspect}"
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
        puts "[next_char] returning: #{str.inspect} from byte: #{b.inspect}"
        return str if str.valid_encoding?

        break if bytes.bytesize >= 64 || b.nil? # too many bytes or EOF
      end
      puts "[next_char] EOF or invalid encoding"
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
        puts "[next_char] consumed: #{ch.inspect}"
      end
    end
    alias skip_chars next_chars

    # it should be safe to assume in average a char is less than 16 bytes
    # def peek_chars(n)
    #   bytes = @io.peek_bytes(n * 16)
    #   puts "[peek_chars] raw peeked bytes=#{bytes.inspect}"
    #   return nil if bytes.nil? || bytes.empty?
    #
    #   str = bytes.dup.force_encoding(@encoding)
    #
    #   if str.valid_encoding?
    #     char_array = str.chars
    #     result = char_array[0, n].join
    #     puts "[peek_chars] returning chars: #{result.inspect}"
    #     return result
    #   end
    #
    #   puts "[peek_chars] returning nil (invalid encoding)"
    #   nil
    # end

    # - it should be safe to assume in average a char is less than 16 bytes
    # - peek_bytes may contain invalid sequences if a multi-byte character is cut
    def peek_chars(n)
      bytes = @io.peek_bytes(n * 16)
      puts "[peek_chars] raw peeked bytes=#{bytes.inspect}"
      return nil if bytes.nil? || bytes.empty?

      str = bytes.dup.force_encoding(@encoding)

      if str.valid_encoding?
        result = str.chars.first(n).join
        puts "[peek_chars] returning chars: #{result.inspect}"
        return result
      else
        # this fixes the issue with partially cut multi-byte characters
        valid_prefix = bytes.byteslice(0, bytes.length)
                            .force_encoding(@encoding)
                            .scrub('')
                            .chars
                            .first(n)
                            .join
        puts "[peek_chars] returning partial (scrubbed) chars: #{valid_prefix.inspect}"
        return valid_prefix unless valid_prefix.empty?
      end

      puts "[peek_chars] returning nil (invalid encoding)"
      nil
    end
    # rubocop:enable Naming/MethodParameterName
  end
end
