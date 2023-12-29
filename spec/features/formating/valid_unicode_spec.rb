# frozen_string_literal: true

require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'valid unicode' do
  it 'loads file with unicode strings' do
    options = {}
    data = SmarterCSV.process("#{fixture_path}/valid_unicode.csv", options)
    expect(data.flatten.size).to eq 4
    expect(data[0][:artist]).to eq 'Кино'
    expect(data[0][:track]).to eq 'Мама, мы все сошли с ума'
    expect(data[0][:album]).to eq 'Группа Крови'
    expect(data[0][:label]).to eq 'Moroz Records'
    expect(data[0][:year]).to eq 1998

    expect(data[0]).to eq data[1]

    expect(data[2][:artist]).to eq 'Rammstein'
    expect(data[2][:track]).to eq 'Frühling in Paris'
    expect(data[2][:album]).to eq 'Liebe ist für alle da'
    expect(data[2][:label]).to eq 'Vagrant'
    expect(data[2][:year]).to eq 2009

    expect(data[2]).to eq data[3]
  end

  it 'loads file with unicode strings, when forcing utf8' do
    options = {force_utf8: true}
    data = SmarterCSV.process("#{fixture_path}/valid_unicode.csv", options)
    expect(data.flatten.size).to eq 4
    expect(data[0][:artist]).to eq 'Кино'
    expect(data[0][:track]).to eq 'Мама, мы все сошли с ума'
    expect(data[0][:album]).to eq 'Группа Крови'
    expect(data[0][:label]).to eq 'Moroz Records'
    expect(data[0][:year]).to eq 1998

    expect(data[0]).to eq data[1]

    expect(data[2][:artist]).to eq 'Rammstein'
    expect(data[2][:track]).to eq 'Frühling in Paris'
    expect(data[2][:album]).to eq 'Liebe ist für alle da'
    expect(data[2][:label]).to eq 'Vagrant'
    expect(data[2][:year]).to eq 2009

    expect(data[2]).to eq data[3]
  end

  it 'loads file with unicode strings, when loading from binary input' do
    options = {file_encoding: 'binary'}
    data = SmarterCSV.process("#{fixture_path}/valid_unicode.csv", options)
    expect(data.flatten.size).to eq 4
    expect(data[0][:artist]).to eq 'Кино'
    expect(data[0][:track]).to eq 'Мама, мы все сошли с ума'
    expect(data[0][:album]).to eq 'Группа Крови'
    expect(data[0][:label]).to eq 'Moroz Records'
    expect(data[0][:year]).to eq 1998

    expect(data[0]).to eq data[1]

    expect(data[2][:artist]).to eq 'Rammstein'
    expect(data[2][:track]).to eq 'Frühling in Paris'
    expect(data[2][:album]).to eq 'Liebe ist für alle da'
    expect(data[2][:label]).to eq 'Vagrant'
    expect(data[2][:year]).to eq 2009

    expect(data[2]).to eq data[3]
  end

  it 'loads file with unicode strings, when forcing utf8 with binary input' do
    options = {file_encoding: 'binary', force_utf8: true}
    data = SmarterCSV.process("#{fixture_path}/valid_unicode.csv", options)
    expect(data.flatten.size).to eq 4
    expect(data[0][:artist]).to eq 'Кино'
    expect(data[0][:track]).to eq 'Мама, мы все сошли с ума'
    expect(data[0][:album]).to eq 'Группа Крови'
    expect(data[0][:label]).to eq 'Moroz Records'
    expect(data[0][:year]).to eq 1998

    expect(data[0]).to eq data[1]

    expect(data[2][:artist]).to eq 'Rammstein'
    expect(data[2][:track]).to eq 'Frühling in Paris'
    expect(data[2][:album]).to eq 'Liebe ist für alle da'
    expect(data[2][:label]).to eq 'Vagrant'
    expect(data[2][:year]).to eq 2009

    expect(data[2]).to eq data[3]
  end
end
