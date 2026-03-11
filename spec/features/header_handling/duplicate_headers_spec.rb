# frozen_string_literal: true

fixture_path = 'spec/fixtures'

# CSV with empty headers: "name,,"
# empty_headers.csv:
#   name,,
#   Carl,Edward,Sagan

describe 'empty headers in CSV file' do
  it 'assigns column_N keys to empty headers using missing_header_prefix (default)' do
    data = SmarterCSV.process("#{fixture_path}/empty_headers.csv")
    expect(data.size).to eq 1
    expect(data.first).to eq({ name: 'Carl', column_1: 'Edward', column_2: 'Sagan' })
  end

  it 'does not silently drop values for empty headers' do
    data = SmarterCSV.process("#{fixture_path}/empty_headers.csv")
    expect(data.first.size).to eq 3
    expect(data.first.values).to eq ['Carl', 'Edward', 'Sagan']
  end

  it 'respects a custom missing_header_prefix' do
    data = SmarterCSV.process("#{fixture_path}/empty_headers.csv", missing_header_prefix: 'field_')
    expect(data.first).to eq({ name: 'Carl', field_1: 'Edward', field_2: 'Sagan' })
  end

  # With strip_whitespace: true (default), whitespace-only headers are stripped to ""
  # before disambiguate_headers runs, where blank?() catches them.
  context 'with whitespace-only headers (strip_whitespace: true, default)' do
    it 'treats a spaces-only header ("  ") as blank and auto-names it' do
      data = SmarterCSV.parse("name,  ,value\nCarl,Edward,Sagan\n")
      expect(data.first).to eq({ name: 'Carl', column_1: 'Edward', value: 'Sagan' })
    end

    it 'treats a tab-only header ("\t") as blank and auto-names it' do
      data = SmarterCSV.parse("name,\t,value\nCarl,Edward,Sagan\n")
      expect(data.first).to eq({ name: 'Carl', column_1: 'Edward', value: 'Sagan' })
    end
  end

  # With strip_whitespace: false, whitespace-only headers are NOT stripped first.
  # header_transformations normalizes them to "" before gsub so they don't become "_".
  context 'with whitespace-only headers (strip_whitespace: false)' do
    it 'treats a spaces-only header ("  ") as blank and auto-names it' do
      data = SmarterCSV.parse("name,  ,value\nCarl,Edward,Sagan\n", strip_whitespace: false)
      expect(data.first).to eq({ name: 'Carl', column_1: 'Edward', value: 'Sagan' })
    end

    it 'treats a tab-only header ("\t") as blank and auto-names it' do
      data = SmarterCSV.parse("name,\t,value\nCarl,Edward,Sagan\n", strip_whitespace: false)
      expect(data.first).to eq({ name: 'Carl', column_1: 'Edward', value: 'Sagan' })
    end
  end

  it 'skips ahead when auto-generated name collides with an existing header' do
    data = SmarterCSV.parse("column_1,name,\nAlbert,Bernard,Cecil\n")
    expect(data.first).to eq({ column_1: 'Albert', name: 'Bernard', column_2: 'Cecil' })
  end

  it 'skips multiple collisions to find the next available name' do
    data = SmarterCSV.parse("column_1,column_2,\nAlbert,Bernard,Cecil\n")
    expect(data.first).to eq({ column_1: 'Albert', column_2: 'Bernard', column_3: 'Cecil' })
  end

  it 'assigns column_N keys when all headers are empty' do
    data = SmarterCSV.parse(",,,\n1,2,3,4\n")
    expect(data.first).to eq({ column_1: 1, column_2: 2, column_3: 3, column_4: 4 })
  end

  it 'produces string keys with keep_original_headers: true' do
    data = SmarterCSV.parse("name,,\nCarl,Edward,Sagan\n", keep_original_headers: true)
    expect(data.first).to eq({ 'name' => 'Carl', 'column_1' => 'Edward', 'column_2' => 'Sagan' })
    expect(data.first.keys.map(&:class).uniq).to eq [String]
  end

  it 'produces string keys with strings_as_keys: true' do
    data = SmarterCSV.parse("name,,\nCarl,Edward,Sagan\n", strings_as_keys: true)
    expect(data.first).to eq({ 'name' => 'Carl', 'column_1' => 'Edward', 'column_2' => 'Sagan' })
    expect(data.first.keys.map(&:class).uniq).to eq [String]
  end

  it 'handles a mix of named, empty, and duplicate headers' do
    data = SmarterCSV.parse("name,name,,name\nAlbert,Bernard,Cecil,Daniel\n")
    expect(data.first[:name]).to eq 'Albert'
    expect(data.first[:column_1]).to eq 'Cecil'
    expect(data.first.size).to eq 4
  end
end

describe 'duplicate headers' do
  describe 'without special handling / default behavior' do
    it 'does not raise error when duplicate_header_suffix is given' do
      expect do
        SmarterCSV.process("#{fixture_path}/duplicate_headers.csv", {duplicate_header_suffix: ''})
      end.not_to raise_exception
    end

    it 'raises error when user_provided_headers with duplicates are given' do
      expect do
        options = {user_provided_headers: %i[a b c d a], headers_in_file: false}
        SmarterCSV.process("#{fixture_path}/duplicate_headers.csv", options)
      end.to raise_exception(SmarterCSV::DuplicateHeaders) do |error|
        expect(error.headers).to eq [:a]
      end
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
        end.to raise_exception(SmarterCSV::DuplicateHeaders) do |error|
          expect(error.headers).to eq [:email]
        end
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
        options.merge!({user_provided_headers: %i[a b c a a], headers_in_file: false})
        expect do
          SmarterCSV.process("#{fixture_path}/duplicate_headers.csv", options)
        end.to raise_exception(SmarterCSV::DuplicateHeaders) do |error|
          expect(error.headers).to eq [:a]
        end
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
        options.merge!({user_provided_headers: %i[a b c a a], headers_in_file: false})
        expect do
          SmarterCSV.process("#{fixture_path}/duplicate_headers.csv", options)
        end.to raise_exception(SmarterCSV::DuplicateHeaders) do |error|
          expect(error.headers).to eq [:a]
        end
      end
    end
  end
end
