# frozen_string_literal: true

module SmarterCSV
  class << self
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
  end
end
