# frozen_string_literal: true

# ------------------------------------------------------------------------------------------
# Contract: when the public C parser entrypoints (parse_csv_line_c, parse_line_to_hash_c,
# parse_line_to_hash_ctx_c) are called with a nil line, they return a defensive shape
# rather than raising. In production the Reader's read loop exits on EOF (nil) before
# calling these, so the guards rarely fire — but the entrypoints are part of the public
# Parser module surface and are reachable directly. These specs pin the contract so it
# can't drift unnoticed.
#
# Calls go through `Klass.new.send(:method, ...)` — the same pattern other Parser specs
# (e.g. max_size_spec.rb) use, because the C methods are private instance methods on
# the included module (defined via rb_define_module_function in the C extension).
#
# These are C-only contract specs: the entrypoints don't exist on non-MRI runtimes
# (JRuby, TruffleRuby), so the file is a no-op there.
# ------------------------------------------------------------------------------------------

return if RUBY_ENGINE != 'ruby'

class NilInputProbe
  include SmarterCSV::Parser
end

describe "Parser C entrypoints — nil line input" do
  let(:probe) { NilInputProbe.new }

  it "parse_csv_line_c(nil, ...) returns [[], 0]" do
    result = probe.send(
      :parse_csv_line_c,
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

  it "parse_line_to_hash_c(nil, headers, options) returns [nil, 0]" do
    result = probe.send(:parse_line_to_hash_c, nil, [:a, :b], {})
    expect(result).to eq([nil, 0])
  end

  it "parse_line_to_hash_ctx_c(nil, ctx) returns [nil, 0]" do
    ctx = probe.send(:new_parse_context_c, [:a, :b], {})
    result = probe.send(:parse_line_to_hash_ctx_c, nil, ctx)
    expect(result).to eq([nil, 0])
  end
end
