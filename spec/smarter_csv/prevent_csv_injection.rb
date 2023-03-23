# frozen_string_literal: true

require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'handling of additional trailing column separators' do
  let(:file) { "#{fixture_path}/csv_injection.csv" }

  describe '' do
    let(:data) { SmarterCSV.process(file, {prevent_csv_injection: true, strip_whitespace: false}) }
    let(:data_prevent_csv_injection_disabled) { SmarterCSV.process(file, {prevent_csv_injection: false, strip_whitespace: false}) }
    it 'removes macros safely' do
      data.each do |x|
        expect(x[:age]).to be_nil
      end
    end

    it 'processing works normally' do
      data_prevent_csv_injection_disabled.each do |x|
        expect(x[:age]).not_to be_nil
      end
    end
  end
end
