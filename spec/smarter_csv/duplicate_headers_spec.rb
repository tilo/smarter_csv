require 'spec_helper'

fixture_path = 'spec/fixtures'

describe 'duplicate headers' do
  describe 'without special handling / default behavior' do
    it 'raises error on duplicate headers' do
      expect {
        SmarterCSV.process("#{fixture_path}/duplicate_headers.csv", {})
      }.to raise_exception(SmarterCSV::DuplicateHeaders)
    end

    it 'does not raise error when duplicate_header_suffix is given' do
      expect {
        SmarterCSV.process("#{fixture_path}/duplicate_headers.csv", {duplicate_header_suffix: ''})
      }.not_to raise_exception
    end

    it 'does not raise error when user_provided_headers are given' do
      expect {
        options = {:user_provided_headers => [:a,:b,:c,:d,:a]}
        SmarterCSV.process("#{fixture_path}/duplicate_headers.csv", options)
      }.not_to raise_exception
    end

    it 'raises error on duplicate headers, when attempting to do key_mapping' do
      # the mapping is right, but the underlying csv file is bad
      options = {:key_mapping => {:email => :a, :firstname => :b, :lastname => :c, :manager_email => :d, :age => :e} }
      expect {
        SmarterCSV.process("#{fixture_path}/duplicate_headers.csv", options)
      }.to raise_exception(SmarterCSV::DuplicateHeaders)
    end
  end

  describe 'with special handling' do
    context 'with given suffix' do
      let(:options) { {duplicate_header_suffix: '_'} }

      it 'reads whole file' do
        data = SmarterCSV.process("#{fixture_path}/duplicate_headers.csv", options)
        expect(data.size).to eq 2
      end

      it 'generates the correct keys' do
        data = SmarterCSV.process("#{fixture_path}/duplicate_headers.csv", options)
        expect(data.first.keys).to eq [:email, :firstname, :lastname, :email_2, :age]
      end

      it 'enumerates when duplicate headers are given' do
        options.merge!({:user_provided_headers => [:a,:b,:c,:a,:a]})
        data = SmarterCSV.process("#{fixture_path}/duplicate_headers.csv", options)
        expect(data.first.keys).to eq [:a, :b, :c, :a_2, :a_3]
      end

      it 'can remap duplicated headers' do
        options.merge!({:key_mapping => {:email => :a, :firstname => :b, :lastname => :c, :email_2 => :d, :age => :e}})
        data = SmarterCSV.process("#{fixture_path}/duplicate_headers.csv", options)
        expect(data.first).to eq({a: 'tom@bla.com', b: 'Tom', c: 'Sawyer', d: 'mike@bla.com', e: 34})
      end
    end

    context 'with empty suffix' do
      let(:options) { {duplicate_header_suffix: ''} }

      it 'reads whole file' do
        data = SmarterCSV.process("#{fixture_path}/duplicate_headers.csv", options)
        expect(data.size).to eq 2
      end

      it 'generates the correct keys' do
        data = SmarterCSV.process("#{fixture_path}/duplicate_headers.csv", options)
        expect(data.first.keys).to eq [:email, :firstname, :lastname, :email2, :age]
      end

      it 'enumerates when duplicate headers are given' do
        options.merge!({:user_provided_headers => [:a,:b,:c,:a,:a]})
        data = SmarterCSV.process("#{fixture_path}/duplicate_headers.csv", options)
        expect(data.first.keys).to eq [:a, :b, :c, :a2, :a3]
      end
    end
  end
end
