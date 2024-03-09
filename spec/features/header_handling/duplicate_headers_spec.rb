# frozen_string_literal: true

fixture_path = 'spec/fixtures'

describe 'duplicate headers' do
  describe 'without special handling / default behavior' do
    it 'does not raise error when duplicate_header_suffix is given' do
      expect do
        SmarterCSV.process("#{fixture_path}/duplicate_headers.csv", {duplicate_header_suffix: ''})
      end.not_to raise_exception
    end

    it 'raises error when user_provided_headers with duplicates are given' do
      expect do
        options = {user_provided_headers: %i[a b c d a]}
        SmarterCSV.process("#{fixture_path}/duplicate_headers.csv", options)
      end.to raise_exception(SmarterCSV::DuplicateHeaders)
    end

    it 'can remap duplicated headers' do
      options ={key_mapping: {email: :a, firstname: :b, lastname: :c, email2: :d, age: :e}}
      data = SmarterCSV.process("#{fixture_path}/duplicate_headers.csv", options)
      expect(data.first).to eq({a: 'tom@bla.com', b: 'Tom', c: 'Sawyer', d: 'mike@bla.com', e: 34})
    end
  end

  describe 'with special handling' do
    context 'when suffix is set to nil' do
      let(:options) { {duplicate_header_suffix: nil} }

      it 'raises error on duplicate headers in the input file' do
        expect do
          SmarterCSV.process("#{fixture_path}/duplicate_headers.csv", options)
        end.to raise_exception(SmarterCSV::DuplicateHeaders)
      end
    end

    context 'with given suffix' do
      let(:options) { {duplicate_header_suffix: '_'} }

      it 'reads whole file' do
        data = SmarterCSV.process("#{fixture_path}/duplicate_headers.csv", options)
        expect(data.size).to eq 2
      end

      it 'generates the correct keys' do
        data = SmarterCSV.process("#{fixture_path}/duplicate_headers.csv", options)
        expect(data.first.keys).to eq %i[email firstname lastname email_2 age]
      end

      it 'raises when duplicate headers are given' do
        options.merge!({user_provided_headers: %i[a b c a a]})
        expect do
          SmarterCSV.process("#{fixture_path}/duplicate_headers.csv", options)
        end.to raise_exception(SmarterCSV::DuplicateHeaders)
      end

      it 'can remap duplicated headers' do
        options.merge!({key_mapping: {email: :a, firstname: :b, lastname: :c, email_2: :d, age: :e}})
        data = SmarterCSV.process("#{fixture_path}/duplicate_headers.csv", options)
        expect(data.first).to eq({a: 'tom@bla.com', b: 'Tom', c: 'Sawyer', d: 'mike@bla.com', e: 34})
      end
    end

    context 'with different suffix' do
      let(:options) { {duplicate_header_suffix: ':'} }

      it 'reads whole file' do
        data = SmarterCSV.process("#{fixture_path}/duplicate_headers.csv", options)
        expect(data.size).to eq 2
      end

      it 'generates the correct keys' do
        data = SmarterCSV.process("#{fixture_path}/duplicate_headers.csv", options)
        expect(data.first.keys).to eq %i[email firstname lastname email:2 age]
      end

      it 'raises when duplicate headers are given' do
        options.merge!({user_provided_headers: %i[a b c a a]})
        expect do
          SmarterCSV.process("#{fixture_path}/duplicate_headers.csv", options)
        end.to raise_exception(SmarterCSV::DuplicateHeaders)
      end
    end
  end
end
