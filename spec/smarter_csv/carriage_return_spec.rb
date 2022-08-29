# frozen_string_literal: true

require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'process files with line endings explicitly pre-specified' do
  shared_examples "reads contents correctly" do
    it "reads contents correctly" do
      expect(data.flatten.size).to eq 8
      expect(data[0][:name]).to eq "Anfield"
      expect(data[0][:street]).to eq "Anfield Road"
      expect(data[0][:city]).to eq "Liverpool"
      expect(data[1][:name]).to eq ["Highbury", "Highbury House"].join(sep)
      expect(data[2][:street]).to eq ["Sir Matt ", "Busby Way"].join(sep)
      expect(data[3][:city]).to eq ["Newcastle-upon-tyne ", "Tyne and Wear"].join(sep)
      expect(data[4][:name]).to eq ["White Hart Lane", "(The Lane)"].join(sep)
      expect(data[4][:street]).to eq ["Bill Nicholson Way ", "748 High Rd"].join(sep)
      expect(data[4][:city]).to eq %w[Tottenham London].join(sep)
      expect(data[5][:name]).to eq "Stamford Bridge"
      expect(data[5][:street]).to eq ["Fulham Road", "London"].join(sep)
      expect(data[5][:city]).to be_nil
      expect(data[6][:name]).to eq ["Etihad Stadium", "Rowsley St", "Manchester"].join(sep)
      expect(data[7][:name]).to eq "Goodison"
      expect(data[7][:street]).to eq "Goodison Road"
      expect(data[7][:city]).to eq "Liverpool"
    end
  end

  describe "with given row_sep" do
    let(:options) { {row_sep: sep}}
    let(:data) { SmarterCSV.process("#{fixture_path}/#{file}", options) }

    it_behaves_like "reads contents correctly" do
      let(:file) { "carriage_returns_n.csv" }
      let(:sep) { "\n" }
    end

    it_behaves_like "reads contents correctly" do
      let(:file) { "carriage_returns_r.csv" }
      let(:sep) { "\r" }
    end

    it_behaves_like "reads contents correctly" do
      let(:file) { "carriage_returns_rn.csv" }
      let(:sep) { "\r\n" }
    end
  end

  describe "with auto row_sep" do
    let(:options) { {row_sep: :auto}}
    let(:data) { SmarterCSV.process("#{fixture_path}/#{file}", options) }

    it_behaves_like "reads contents correctly" do
      let(:file) { "carriage_returns_n.csv" }
      let(:sep) { "\n" }
    end

    it_behaves_like "reads contents correctly" do
      let(:file) { "carriage_returns_r.csv" }
      let(:sep) { "\r" }
    end

    it_behaves_like "reads contents correctly" do
      let(:file) { "carriage_returns_rn.csv" }
      let(:sep) { "\r\n" }
    end
  end

  describe "with auto row_sep" do
    let(:options) { {row_sep: 'auto'}}
    let(:data) { SmarterCSV.process("#{fixture_path}/#{file}", options) }

    it_behaves_like "reads contents correctly" do
      let(:file) { "carriage_returns_n.csv" }
      let(:sep) { "\n" }
    end

    it_behaves_like "reads contents correctly" do
      let(:file) { "carriage_returns_r.csv" }
      let(:sep) { "\r" }
    end

    it_behaves_like "reads contents correctly" do
      let(:file) { "carriage_returns_rn.csv" }
      let(:sep) { "\r\n" }
    end
  end

  it 'should process a file with more quoted text carriage return characters (\r) than line ending characters (\n)' do
    row_sep = "\n"
    text_sep = "\r"
    data = SmarterCSV.process("#{fixture_path}/carriage_returns_quoted.csv", {row_sep: row_sep})
    expect(data.flatten.size).to eq 2
    expect(data[0][:band]).to eq "New Order"
    expect(data[0][:members]).to eq ["Bernard Sumner", "Peter Hook", "Stephen Morris", "Gillian Gilbert"].join(text_sep)
    expect(data[0][:albums]).to eq ["Movement", "Power, Corruption and Lies", "Low-Life", "Brotherhood", "Substance"].join(text_sep)
    expect(data[1][:band]).to eq "Led Zeppelin"
    expect(data[1][:members]).to eq ["Jimmy Page", "Robert Plant", "John Bonham", "John Paul Jones"].join(text_sep)
    expect(data[1][:albums]).to eq ["Led Zeppelin", "Led Zeppelin II", "Led Zeppelin III", "Led Zeppelin IV"].join(text_sep)
  end

  describe 'process files with line endings in automatic mode' do
    let(:options) { { row_sep: :auto } }

    it 'should process a file with more quoted text carriage return characters (\r) than line ending characters (\n)' do
      row_sep = "\n"
      text_sep = "\r"
      data = SmarterCSV.process("#{fixture_path}/carriage_returns_quoted.csv", options)
      expect(data.flatten.size).to eq 2
      expect(data[0][:band]).to eq "New Order"
      expect(data[0][:members]).to eq ["Bernard Sumner", "Peter Hook", "Stephen Morris", "Gillian Gilbert"].join(text_sep)
      expect(data[0][:albums]).to eq ["Movement", "Power, Corruption and Lies", "Low-Life", "Brotherhood", "Substance"].join(text_sep)
      expect(data[1][:band]).to eq "Led Zeppelin"
      expect(data[1][:members]).to eq ["Jimmy Page", "Robert Plant", "John Bonham", "John Paul Jones"].join(text_sep)
      expect(data[1][:albums]).to eq ["Led Zeppelin", "Led Zeppelin II", "Led Zeppelin III", "Led Zeppelin IV"].join(text_sep)
    end
  end

  shared_examples "reads contents correctly with line numbers" do
    it "reads contents correctly with line numbers" do
      expect(data.flatten.size).to eq 8
      expect(data[0][:name]).to eq "Anfield"
      expect(data[0][:street]).to eq "Anfield Road"
      expect(data[0][:city]).to eq "Liverpool"
      expect(data[0][:csv_line_number]).to eq 2

      expect(data[1][:name]).to eq ["Highbury", "Highbury House"].join(sep)
      expect(data[1][:csv_line_number]).to eq 3

      expect(data[2][:street]).to eq ["Sir Matt ", "Busby Way"].join(sep)
      expect(data[2][:csv_line_number]).to eq 4

      expect(data[3][:city]).to eq ["Newcastle-upon-tyne ", "Tyne and Wear"].join(sep)
      expect(data[3][:csv_line_number]).to eq 5

      expect(data[4][:name]).to eq ["White Hart Lane", "(The Lane)"].join(sep)
      expect(data[4][:street]).to eq ["Bill Nicholson Way ", "748 High Rd"].join(sep)
      expect(data[4][:city]).to eq %w[Tottenham London].join(sep)
      expect(data[4][:csv_line_number]).to eq 6

      expect(data[5][:name]).to eq "Stamford Bridge"
      expect(data[5][:street]).to eq ["Fulham Road", "London"].join(sep)
      expect(data[5][:city]).to be_nil
      expect(data[5][:csv_line_number]).to eq 7

      expect(data[6][:name]).to eq ["Etihad Stadium", "Rowsley St", "Manchester"].join(sep)
      expect(data[6][:csv_line_number]).to eq 8

      expect(data[7][:name]).to eq "Goodison"
      expect(data[7][:street]).to eq "Goodison Road"
      expect(data[7][:city]).to eq "Liverpool"
      expect(data[7][:csv_line_number]).to eq 9
    end
  end

  describe "with given row_sep" do
    let(:options) { {with_line_numbers: true, row_sep: sep}}
    let(:data) { SmarterCSV.process("#{fixture_path}/#{file}", options) }

    it_behaves_like "reads contents correctly with line numbers" do
      let(:file) { "carriage_returns_n.csv" }
      let(:sep) { "\n" }
    end

    it_behaves_like "reads contents correctly with line numbers" do
      let(:file) { "carriage_returns_r.csv" }
      let(:sep) { "\r" }
    end

    it_behaves_like "reads contents correctly with line numbers" do
      let(:file) { "carriage_returns_rn.csv" }
      let(:sep) { "\r\n" }
    end
  end

  describe "with auto row_sep" do
    let(:options) { {with_line_numbers: true, row_sep: :auto}}
    let(:data) { SmarterCSV.process("#{fixture_path}/#{file}", options) }

    it_behaves_like "reads contents correctly with line numbers" do
      let(:file) { "carriage_returns_n.csv" }
      let(:sep) { "\n" }
    end

    it_behaves_like "reads contents correctly with line numbers" do
      let(:file) { "carriage_returns_r.csv" }
      let(:sep) { "\r" }
    end

    it_behaves_like "reads contents correctly with line numbers" do
      let(:file) { "carriage_returns_rn.csv" }
      let(:sep) { "\r\n" }
    end
  end
end
