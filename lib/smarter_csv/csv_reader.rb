# frozen_string_literal: true

module SmarterCSV
  class CSVReader
    def initialize(source, options)
      @buffer_size = options[:buffer_size] || (128 * 1024)
      @io = SmarterCSV::BufferedIO.new(source, @buffer_size)
      @encoding = source.respond_to?(:external_encoding) ? source.external_encoding : Encoding::UTF_8
      @row_sep = options[:row_sep]
      @col_sep = options[:col_sep]
      @quote_char = options[:quote_char]
      @double_quote_char = options[:quote_char] * 2
    end

    def read_row_as_fields
      fields = []
      field = +""
      match_buffer = +""
      state = :start_field
      field_pushed = false

      loop do
        char = next_char
        break if char.nil?

        match_buffer << char
        puts "STATE: #{state}, CHAR: #{char.inspect}, MATCH_BUFFER: #{match_buffer.inspect}"

        case state
        when :start_field
          field_pushed = false
          if match_buffer == @quote_char
            # Look ahead: is this the start of an escaped quote or quoted field?
            temp = match_buffer.dup
            temp << (peek_char || "")
            if temp == @double_quote_char
              puts "Double quote detected in start_field"
              field << @quote_char
              match_buffer.clear
              @io.next_byte # consume lookahead
              state = :in_field
            else
              puts "Entering quoted field"
              match_buffer.clear
              state = :in_quoted_field
            end
          elsif match_buffer == @col_sep
            puts "Empty field at start"
            fields << ""
            field_pushed = true
            match_buffer.clear
            state = :start_field
          elsif match_buffer == @row_sep
            puts "Empty field at row_sep"
            fields << ""
            field_pushed = true
            match_buffer.clear
            break
          elsif match_buffer.start_with?(@col_sep, @row_sep, @quote_char)
            next
          else
            puts "Entering unquoted field"
            field << match_buffer[0]
            match_buffer = match_buffer[1..-1] || +""
            state = :in_field
          end

        when :in_field
          if match_buffer == @col_sep
            puts "Field complete in in_field"
            fields << field
            field_pushed = true
            field = +""
            match_buffer.clear
            state = :start_field
          elsif match_buffer.start_with?(@col_sep)
            next
          elsif match_buffer == @row_sep
            puts "Row end in in_field"
            fields << field
            field = +""
            field_pushed = true
            match_buffer.clear
            break
          elsif match_buffer.start_with?(@row_sep)
            next
          elsif match_buffer == @double_quote_char
            puts "Unescaped double quote inside unquoted field"
            field << @quote_char
            match_buffer.clear
          elsif match_buffer.start_with?(@double_quote_char)
            next
          else
            field << match_buffer[0]
            match_buffer = match_buffer[1..-1] || +""
          end

        when :in_quoted_field
          if match_buffer == @double_quote_char
            puts "Escaped quote inside quoted field"
            field << @quote_char
            match_buffer.clear
          elsif match_buffer == @quote_char
            puts "Potential end of quoted field"
            state = :quote_terminated
            match_buffer.clear
          elsif match_buffer.start_with?(@quote_char)
            next
          else
            field << match_buffer[0]
            match_buffer = match_buffer[1..-1] || +""
          end

        when :quote_terminated
          if match_buffer == @quote_char
            puts "Double quote escape after quote_terminated"
            field << @quote_char
            match_buffer.clear
            state = :in_quoted_field
          elsif match_buffer == @col_sep
            puts "Field complete after quote"
            fields << field
            field_pushed = true
            field = +""
            match_buffer.clear
            state = :start_field
          elsif match_buffer == @row_sep
            puts "Row end after quoted field"
            fields << field
            field_pushed = true
            match_buffer.clear
            break
          elsif match_buffer.start_with?(@col_sep, @row_sep, @quote_char)
            next
          else
            puts "Garbage after quoted field"
            field << match_buffer[0]
            match_buffer = match_buffer[1..-1] || +""
            state = :in_field
          end
        end
      end

      # Final field flush after loop (last field without trailing row_sep)
      field << match_buffer unless match_buffer.empty?
      fields << field unless field.empty? || field_pushed

      fields.empty? ? nil : fields
    end

    def read_row
      row = +""
      match_buffer = +""

      while (char = next_char)
        match_buffer << char

        if match_buffer == @row_sep
          row << match_buffer
          return row
        end

        # Continue matching if we're on a valid prefix
        next if @row_sep.start_with?(match_buffer)

        # Flush first char of buffer to row, and try to match again
        row << match_buffer[0]
        match_buffer = match_buffer[1..-1] || +""
      end

      # At EOF: flush what's left
      row << match_buffer unless match_buffer.empty?
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

    def peek_char
      bytes = +""
      while (b = @io.peek_byte)
        bytes << b
        return bytes.force_encoding(@encoding) if bytes.valid_encoding?
        break if bytes.bytesize >= 4

        @io.next_byte
      end
      nil
    end

    def next_char
      bytes = +""
      while (b = @io.peek_byte)
        bytes << b
        return consume(bytes) if bytes.valid_encoding?
        break if bytes.bytesize >= 4

        @io.next_byte
      end
      nil
    end

    private

    def consume(bytes)
      bytes.bytesize.times { @io.next_byte }
      bytes.force_encoding(@encoding)
    end
  end
end
