# frozen_string_literal: true

# ------------------------------------------------------------------------------------------
# Contract: when the public C parser entrypoints (parse_csv_line_c, parse_line_to_hash_c,
# parse_line_to_hash_ctx_c) are called with a nil line, they return a defensive shape
# rather than raising. In production the Reader's read loop exits on EOF (nil) before
# calling these, so the guards rarely fire — but the entrypoints are part of the public
# Parser module surface and are reachable directly. These specs pin the contract so it
# can't drift unnoticed.
# ------------------------------------------------------------------------------------------

describe "Parser C entrypoints — nil line input" do
  describe "SmarterCSV::Parser.parse_csv_line_c(nil, ...)" do
    it "returns [[], 0] (empty array + zero data_size)" do
      result = SmarterCSV::Parser.parse_csv_line_c(
        nil,    # line
        ',',    # col_sep
        '"',    # quote_char
        nil,    # max_size
        false,  # has_quotes_val
        false,  # strip_ws_val
        false,  # allow_escaped_quotes_val
        true,   # quote_boundary_standard_val
        nil     # row_sep_val
      )
      expect(result).to eq([[], 0])
    end
  end

  describe "SmarterCSV::Parser.parse_line_to_hash_c(nil, headers, options)" do
    it "returns [nil, 0]" do
      result = SmarterCSV::Parser.parse_line_to_hash_c(nil, [:a, :b], {})
      expect(result).to eq([nil, 0])
    end
  end

  describe "SmarterCSV::Parser.parse_line_to_hash_ctx_c(nil, ctx)" do
    it "returns [nil, 0]" do
      ctx = SmarterCSV::Parser.new_parse_context_c([:a, :b], {})
      result = SmarterCSV::Parser.parse_line_to_hash_ctx_c(nil, ctx)
      expect(result).to eq([nil, 0])
    end
  end
end
