# frozen_string_literal: true

module SmarterCSV
  module FileIO
    protected

    def readline_with_counts(filehandle, options)
      line = filehandle.readline(options[:row_sep])
      @file_line_count += 1
      @csv_line_count += 1
      line = remove_bom(line) if @csv_line_count == 1
      line
    end

    def skip_lines(filehandle, options)
      options[:skip_lines].to_i.times do
        readline_with_counts(filehandle, options)
      end
    end

    def rewind(filehandle)
      @file_line_count = 0
      @csv_line_count = 0
      filehandle.rewind
    end

    private

    UTF_32_BOM = %w[0 0 fe ff].freeze
    UTF_32LE_BOM = %w[ff fe 0 0].freeze
    UTF_8_BOM = %w[ef bb bf].freeze
    UTF_16_BOM = %w[fe ff].freeze
    UTF_16LE_BOM = %w[ff fe].freeze

    def remove_bom(str)
      str_as_hex = str.bytes.map{|x| x.to_s(16)}
      # if string does not start with one of the bytes, there is no BOM
      return str unless %w[ef fe ff 0].include?(str_as_hex[0])

      return str.byteslice(4..-1) if [UTF_32_BOM, UTF_32LE_BOM].include?(str_as_hex[0..3])
      return str.byteslice(3..-1) if str_as_hex[0..2] == UTF_8_BOM
      return str.byteslice(2..-1) if [UTF_16_BOM, UTF_16LE_BOM].include?(str_as_hex[0..1])

      # :nocov:
      puts "SmarterCSV found unhandled BOM! #{str.chars[0..7].inspect}"
      str
      # :nocov:
    end
  end
end
