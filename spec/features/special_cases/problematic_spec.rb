# frozen_string_literal: true

fixture_path = 'spec/fixtures'

describe 'loading file with UTF-8 characters in the header' do
  # file which caused issues because of UTF-8 characters in the header
  it 'loads the file with force_utf8 flag set' do
    options = {col_sep: ";", force_utf8: true}
    data = SmarterCSV.process("#{fixture_path}/problematic.csv", options)

    expect(data.length).to eq 7
  end

  it 'loads the file with strings as keys' do
    options = {
      file_encoding: 'iso-8859-1:UTF-8', # important!
      col_sep: ";", strings_as_keys: true,
    }
    data = SmarterCSV.process("#{fixture_path}/problematic.csv", options)

    expect(data.length).to eq 7
    expect(data.first.keys.sort).to eq %w[
      compte
      date_de_comptabilisation
      date_opération
      date_valeur
      libellé
      montant
      référence
    ]
  end
end
