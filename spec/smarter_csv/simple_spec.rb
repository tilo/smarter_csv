# frozen_string_literal: true

require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'simple file' do
  let(:options) { {} }
  subject(:data) { SmarterCSV.process("#{fixture_path}/simple.csv", options) }

  it 'loads the csv file without issues' do
    expect(data.size).to eq 4
  end
end
