require "spec_helper"
require "tempfile"

module SharedExamples
  module ItShouldProcessEveryRow
    def self.included(base)
      base.class_eval do
        it "should process every row" do
          result = SmarterCSV.process(new_path, smarter_csv_opts.merge(extra_opts))
          result = result.reduce(:+) if extra_opts[:use_chunks] != false

          result.size.must_equal num_rows_expected
        end
      end
    end
  end
end

describe SmarterCSV do
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
        A,1,2
        A,3,4
        A,5,6
      CSV
    }
    let(:num_rows_expected) { 3 }

    include SharedExamples::ItShouldProcessEveryRow
  end

  describe "with empty values in CSV data" do
    let(:csv_data) {
      unindent <<-CSV
        foo,bar,baz
        B,1,2
        ,,
        B,3,4
        B,5,6
        ,,
      CSV
    }

    describe "and :remove_empty_hashes => true" do
      let(:extra_opts) { { remove_empty_hashes: true } }
      let(:num_rows_expected) { 3 }

      include SharedExamples::ItShouldProcessEveryRow

      describe "and :use_chunks => false" do
        let(:extra_opts)  { { remove_empty_hashes:  true,
                              use_chunks:           false,
                              chunk_size:           nil
                            }
                          }

        include SharedExamples::ItShouldProcessEveryRow

      end
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
