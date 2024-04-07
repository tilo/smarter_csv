# frozen_string_literal: true

require 'smarter_csv'
require 'smarter_csv/header_validations'

RSpec.describe SmarterCSV do
  describe '.header_validations' do
    let(:headers) { ['header1', 'header2', 'header3'] }

    context 'when in V1 mode' do
      let(:options) { { v2_mode: false } }

      it 'passes with no duplicate or missing headers' do
        expect { described_class.header_validations(headers, options) }.not_to raise_error
      end

      context 'with duplicate headers' do
        let(:headers) { ['header1', 'header1', 'header3'] }

        it 'raises a DuplicateHeaders error' do
          expect { described_class.header_validations(headers, options) }.to raise_error(SmarterCSV::DuplicateHeaders)
        end
      end

      context 'with missing required headers' do
        let(:options) { { v2_mode: false, required_keys: ['header1', 'header4'] } }

        it 'raises a MissingKeys error' do
          expect { described_class.header_validations(headers, options) }.to raise_error(SmarterCSV::MissingKeys)
        end
      end
    end

    context 'when in V2 mode' do
      let(:options) { { v2_mode: true, header_validations: [:unique_headers, { required_headers: ['header1', 'header4'] }] } }

      context 'with no duplicate or missing headers' do
        let(:headers) { ['header1', 'header2', 'header3', 'header4'] }

        it 'passes validation' do
          expect { described_class.header_validations(headers, options) }.not_to raise_error
        end
      end

      context 'with missing required headers' do
        let(:headers) { ['header1', 'header2', 'header3'] } # 'header4' is missing

        it 'raises a MissingHeaders error' do
          expect { described_class.header_validations(headers, options) }.to raise_error(SmarterCSV::MissingKeys)
        end
      end

      context 'with duplicate headers' do
        let(:headers) { ['header1', 'header1', 'header3'] }

        it 'raises a DuplicateHeaders error' do
          expect { described_class.header_validations(headers, options) }.to raise_error(SmarterCSV::DuplicateHeaders)
        end
      end

      context 'with missing required headers' do
        it 'raises a MissingHeaders error' do
          expect { described_class.header_validations(headers, options) }.to raise_error(SmarterCSV::MissingKeys)
        end
      end

      context 'with custom validation function' do
        let(:custom_validation) { ->(headers) { raise StandardError, 'Custom validation error' if headers.include?('error_header') } }
        let(:options) { { v2_mode: true, header_validations: [custom_validation] } }

        context 'when custom validation fails' do
          let(:headers) { ['error_header', 'header2', 'header3'] }

          it 'raises a custom error' do
            expect { described_class.header_validations(headers, options) }.to raise_error(StandardError, 'Custom validation error')
          end
        end

        context 'when custom validation passes' do
          it 'passes without errors' do
            expect { described_class.header_validations(headers, options) }.not_to raise_error
          end
        end
      end

      context 'when in V2 mode with Array-based validation' do
        let(:headers) { ['header1', 'header2', 'header3'] }

        context 'with custom Array-based validation' do
          let(:options) do
            {
              v2_mode: true,
              header_validations: [[:custom_validation, 'arg1', 'arg2']]
            }
          end

          before do
            allow(described_class).to receive(:custom_validation).and_return(true)
          end

          it 'calls the specified method with arguments' do
            expect(described_class).to receive(:custom_validation).with(headers, ['arg1', 'arg2'])
            described_class.header_validations_v2(headers, options)
          end
        end
      end

      context 'when in V2 mode with a custom object validation' do
        let(:headers) { ['header1', 'header2', 'header3'] }

        context 'with a custom object that responds to call' do
          let(:custom_validator) { double("CustomValidator") }
          let(:options) do
            {
              v2_mode: true,
              header_validations: [custom_validator]
            }
          end

          it 'calls the call method on the custom object' do
            expect(custom_validator).to receive(:call).with(headers)
            described_class.header_validations_v2(headers, options)
          end
        end
      end

      context 'with an invalid validation type' do
        let(:invalid_validation) { 123 } # Using an integer as an invalid type
        let(:options) { { v2_mode: true, header_validations: [invalid_validation] } }

        it 'raises an IncorrectOption error' do
          expect { described_class.header_validations_v2(headers, options) }.to raise_error(SmarterCSV::IncorrectOption, /Invalid validation type/)
        end
      end
    end
  end
end
