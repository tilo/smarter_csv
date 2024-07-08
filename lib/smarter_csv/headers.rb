# frozen_string_literal: true

module SmarterCSV
  module Headers
    def process_headers(filehandle, options)
      @raw_header = nil # header as it appears in the file
      @headers = nil # the processed headers
      header_array = []
      file_header_size = nil

      # if headers_in_file, get the headers -> We get the number of columns, even when user provided headers
      if options[:headers_in_file] # extract the header line
        # process the header line in the CSV file..
        # the first line of a CSV file contains the header .. it might be commented out, so we need to read it anyhow
        header_line = @raw_header = readline_with_counts(filehandle, options)
        header_line = preprocess_header_line(header_line, options)

        file_header_array, file_header_size = parse(header_line, options)

        file_header_array = header_transformations(file_header_array, options)

      else
        unless options[:user_provided_headers]
          raise SmarterCSV::IncorrectOption, "ERROR: If :headers_in_file is set to false, you have to provide :user_provided_headers"
        end
      end

      if options[:user_provided_headers]
        unless options[:user_provided_headers].is_a?(Array) && !options[:user_provided_headers].empty?
          raise(SmarterCSV::IncorrectOption, "ERROR: incorrect format for user_provided_headers! Expecting array with headers.")
        end

        # use user-provided headers
        user_header_array = options[:user_provided_headers]
        # user_provided_headers: their count should match the headers_in_file if any
        if defined?(file_header_size) && !file_header_size.nil?
          if user_header_array.size != file_header_size
            raise SmarterCSV::HeaderSizeMismatch, "ERROR: :user_provided_headers defines #{user_header_array.size} headers !=  CSV-file has #{file_header_size} headers"
          else
            # we could print out the mapping of file_header_array to header_array here
          end
        end

        header_array = user_header_array
      else
        header_array = file_header_array
      end

      [header_array, header_array.size]
    end

    private

    def preprocess_header_line(header_line, options)
      header_line = enforce_utf8_encoding(header_line, options)
      header_line = remove_comments_from_header(header_line, options)
      header_line = header_line.chomp(options[:row_sep])
      header_line.gsub!(options[:strip_chars_from_headers], '') if options[:strip_chars_from_headers]
      header_line
    end

    def remove_comments_from_header(header, options)
      return header unless options[:comment_regexp]

      header.sub(options[:comment_regexp], '')
    end
  end
end
