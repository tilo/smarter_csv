# frozen_string_literal: true

fixture_path = 'spec/fixtures'

describe ':strings_as_keys option' do
  it 'uses strings as hash keys' do
    options = {strings_as_keys: true}
    data = SmarterCSV.process("#{fixture_path}/basic.csv", options)
    expect(data.size).to eq 5

    data.each do |hash|
      hash.each_key do |key|
        expect(key.class).to eq String # all the keys should be symbols

        expect(%w[first_name last_name dogs cats birds fish]).to include(key)
      end

      expect(hash.size).to be <= 6
    end
  end
end
