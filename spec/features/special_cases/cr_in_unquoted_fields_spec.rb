# frozen_string_literal: true

# Characterization tests for stray \r (CR) in unquoted fields under various
# row_sep settings.
#
# Mirrors the area changed by Ruby CSV PR #346
# (https://github.com/ruby/csv/pull/346, fixes ruby/csv#60):
#
#   Ruby CSV used to reject stray \r in unquoted fields even when row_sep was
#   \n. PR #346 fixed this by checking the actual row separator instead of
#   hardcoding "\r\n".
#
# These specs document SmarterCSV's current behavior on the same edge cases.

[true, false].each do |bool|
  describe "stray \\r in unquoted fields with#{bool ? ' C-' : 'out '}acceleration" do
    let(:options) { { acceleration: bool } }

    context "row_sep: \"\\n\" (LF only)" do
      let(:csv) { "name,note\nAlice,hi\rmid\rend\nBob,plain\n" }

      it "preserves \\r as literal characters in the unquoted field" do
        data = SmarterCSV.parse(csv, options.merge(row_sep: "\n"))
        expect(data.size).to eq 2
        expect(data[0]).to eq(name: "Alice", note: "hi\rmid\rend")
        expect(data[1]).to eq(name: "Bob", note: "plain")
      end
    end

    context "row_sep: \"\\r\\n\" (CRLF)" do
      let(:csv) { "name,note\r\nAlice,hi\rmid\r\nBob,plain\r\n" }

      it "treats lone \\r (not followed by \\n) as literal field content" do
        data = SmarterCSV.parse(csv, options.merge(row_sep: "\r\n"))
        expect(data.size).to eq 2
        expect(data[0]).to eq(name: "Alice", note: "hi\rmid")
        expect(data[1]).to eq(name: "Bob", note: "plain")
      end
    end

    context "row_sep: \"\\r\" (CR only — classic Mac)" do
      let(:csv) { "name,note\rAlice,plain\rBob,other\r" }

      it "treats \\r as the row terminator (no \\r allowed in fields)" do
        data = SmarterCSV.parse(csv, options.merge(row_sep: "\r"))
        expect(data.size).to eq 2
        expect(data[0]).to eq(name: "Alice", note: "plain")
        expect(data[1]).to eq(name: "Bob", note: "other")
      end
    end

    context "row_sep: :auto with stray \\r in unquoted fields and \\n separators" do
      let(:csv) { "name,note\nAlice,hi\rmid\nBob,plain\n" }

      it "auto-detects \\n and preserves \\r in the field" do
        data = SmarterCSV.parse(csv, options.merge(row_sep: :auto))
        expect(data.size).to eq 2
        expect(data[0]).to eq(name: "Alice", note: "hi\rmid")
        expect(data[1]).to eq(name: "Bob", note: "plain")
      end
    end
  end
end
