require "minitest/autorun"
require "tempfile"
require "smarter_csv"

module SharedExamples
  module ItShouldProcessEveryRow
    def self.included(base)
      base.class_eval do
        it "should process every row" do
          chunks  = SmarterCSV.process(new_path, smarter_csv_opts.merge(extra_opts))
          rows    = chunks.reduce(:+)

          rows.size.must_equal num_rows_expected
        end
      end
    end
  end
end

describe SmarterCSV do
  let(:row_skip_match) { /^#/ } # Don't count comment lines
  let(:smarter_csv_opts) { { chunk_size: 2 } }
  let(:extra_opts) { {} }

  let(:new_path) do
    path = nil
    Tempfile.open(['smarter_csv_spec', '.csv']) do |temp|
      path = temp.path
      temp << csv_data
    end
    path
  end

  describe "with normal CSV data" do
    let(:csv_data) {
      unindent <<-CSV
        foo,bar,baz
        1,2,3 
        4,5,6
        7,8,9 
      CSV
    }
    let(:num_rows_expected) { 3 }

    include SharedExamples::ItShouldProcessEveryRow
  end

  describe "with empty values in CSV data" do
    let(:csv_data) {
      unindent <<-CSV
        foo,bar,baz
        1,2,3
        ,,
        4,5,6
        7,8,9
        ,,
      CSV
    }

    describe "and :remove_empty_hashes => true" do
      let(:extra_opts) { { remove_empty_hashes: true } }
      let(:num_rows_expected) { 3 }

      include SharedExamples::ItShouldProcessEveryRow
    end

    describe "and :remove_empty_hashes => false" do
      let(:extra_opts) { { remove_empty_hashes: false } }
      let(:num_rows_expected) { 5 }

      include SharedExamples::ItShouldProcessEveryRow
    end
  end
end

def unindent(str)
  str.sub(/^(\s+)/, '').gsub(/^#{ $~ }/, '')
end
