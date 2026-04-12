# frozen_string_literal: true

module SmarterCSV
  class Writer
    module Options
      DEFAULT_OPTIONS = {
        col_sep: ',',
        row_sep: $/,
        quote_char: '"',
        force_quotes: false,
        quote_headers: false,
        disable_auto_quoting: false,
        value_converters: {},
        encoding: nil,
        write_nil_value: '',
        write_empty_value: '',
        write_bom: false,
        write_headers: true,
        header_converter: nil,
        discover_headers: true,
        headers: [],
        map_headers: {},
      }.freeze
    end
  end
end
