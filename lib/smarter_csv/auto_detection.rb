# frozen_string_literal: true

module SmarterCSV
  class << self
    protected

    # If file has headers, then guesses column separator from headers.
    # Otherwise guesses column separator from contents.
    # Raises exception if none is found.
    def guess_column_separator(filehandle, options)
      skip_lines(filehandle, options)

      delimiters = [',', "\t", ';', ':', '|']

      line = nil
      has_header = options[:headers_in_file]
      candidates = Hash.new(0)
      count = has_header ? 1 : 5
      count.times do
        line = readline_with_counts(filehandle, options)
        delimiters.each do |d|
          escaped_quote = Regexp.escape(options[:quote_char])

          # Count only non-quoted occurrences of the delimiter
          non_quoted_text = line.split(/#{escaped_quote}[^#{escaped_quote}]*#{escaped_quote}/).join

          candidates[d] += non_quoted_text.scan(d).count
        end
      rescue EOFError # short files
        break
      end
      rewind(filehandle)

      if candidates.values.max == 0
        # if the header only contains
        return ',' if line.chomp(options[:row_sep]) =~ /^\w+$/

        raise SmarterCSV::NoColSepDetected
      end

      candidates.key(candidates.values.max)
    end

    # limitation: this currently reads the whole file in before making a decision
    def guess_line_ending(filehandle, options)
      counts = {"\n" => 0, "\r" => 0, "\r\n" => 0}
      quoted_char = false

      # count how many of the pre-defined line-endings we find
      # ignoring those contained within quote characters
      last_char = nil
      lines = 0
      filehandle.each_char do |c|
        quoted_char = !quoted_char if c == options[:quote_char]
        next if quoted_char

        if last_char == "\r"
          if c == "\n"
            counts["\r\n"] += 1
          else
            counts["\r"] += 1 # \r are counted after they appeared
          end
        elsif c == "\n"
          counts["\n"] += 1
        end
        last_char = c
        lines += 1
        break if options[:auto_row_sep_chars] && options[:auto_row_sep_chars] > 0 && lines >= options[:auto_row_sep_chars]
      end
      rewind(filehandle)

      counts["\r"] += 1 if last_char == "\r"
      # find the most frequent key/value pair:
      most_frequent_key, _count = counts.max_by{|_, v| v}
      most_frequent_key
    end
  end
end
