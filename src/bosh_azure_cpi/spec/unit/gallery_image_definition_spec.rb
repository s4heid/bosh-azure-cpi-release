# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::GalleryImageDefinition do
  subject(:image_definition) { described_class.new(stemcell_metadata) }

  let(:noble_metadata) do
    {
      'name' => 'bosh-azure-hyperv-ubuntu-noble',
      'os_type' => 'linux',
      'architecture' => 'x86_64',
      'generation' => 'gen2',
      'security_type' => 'TrustedLaunchSupported'
    }
  end
  let(:stemcell_metadata) { noble_metadata }

  describe '#name' do
    it 'is composed of stemcell series, generation, architecture and security type' do
      expect(image_definition.name).to eq('bosh-azure-hyperv-ubuntu-noble-gen2-x64-tls')
    end

    context 'for an arm64 stemcell of the same series' do
      let(:stemcell_metadata) { noble_metadata.merge('architecture' => 'arm64') }

      it 'differs from the name for x64 stemcells' do
        expect(image_definition.name).to eq('bosh-azure-hyperv-ubuntu-noble-gen2-arm64-tls')
      end
    end

    context 'for a stemcell that specifies neither generation nor architecture' do
      let(:stemcell_metadata) { { 'name' => 'bosh-azure-hyperv-ubuntu-jammy-go_agent', 'os_type' => 'linux' } }

      it 'assumes gen1 and x64' do
        expect(image_definition.name).to eq('bosh-azure-hyperv-ubuntu-jammy-go_agent-gen1-x64')
      end
    end

    describe 'security type' do
      {
        'Standard' => 'std',
        'TrustedLaunch' => 'tl',
        'TrustedLaunchSupported' => 'tls',
        'ConfidentialVM' => 'cvm',
        'ConfidentialVMSupported' => 'cvms',
        'TrustedLaunchAndConfidentialVmSupported' => 'tlcvms'
      }.each do |security_type, abbreviation|
        it "abbreviates '#{security_type}' as '#{abbreviation}'" do
          definition = described_class.new(noble_metadata.merge('security_type' => security_type))

          expect(definition.name).to eq("bosh-azure-hyperv-ubuntu-noble-gen2-x64-#{abbreviation}")
        end
      end

      it 'ignores the case' do
        definition = described_class.new(noble_metadata.merge('security_type' => 'trustedlaunchsupported'))

        expect(definition.name).to eq('bosh-azure-hyperv-ubuntu-noble-gen2-x64-tls')
      end

      it 'is omitted when the stemcell does not specify one' do
        definition = described_class.new(noble_metadata.except('security_type'))

        expect(definition.name).to eq('bosh-azure-hyperv-ubuntu-noble-gen2-x64')
      end

      it 'is omitted for gen1 stemcells, which do not support security types' do
        definition = described_class.new(noble_metadata.merge('generation' => 'gen1'))

        expect(definition.name).to eq('bosh-azure-hyperv-ubuntu-noble-gen1-x64')
      end

      it 'is rejected when unknown' do
        definition = described_class.new(noble_metadata.merge('security_type' => 'Unknown'))

        expect { definition.name }.to raise_error(Bosh::Clouds::CloudError, /Unsupported security_type 'Unknown'/)
      end
    end

    context 'when the name would exceed 64 characters' do
      let(:long_series) { 'bosh-azure-hyperv-ubuntu-noble-fips-with-an-extraordinarily-long-custom-suffix' }
      let(:stemcell_metadata) { noble_metadata.merge('name' => long_series) }

      it 'shortens the series, but keeps generation, architecture and security type' do
        expect(image_definition.name).to match(/\Abosh-azure-hyperv-ubuntu-noble-fips-with-a-\h{8}-gen2-x64-tls\z/)
        expect(image_definition.name.length).to eq(64)
      end

      it 'stays unique for series that only differ in the shortened part' do
        other_definition = described_class.new(noble_metadata.merge('name' => "#{long_series}-2"))

        expect(other_definition.name).not_to eq(image_definition.name)
      end
    end

    it 'raises an error when the stemcell name is missing' do
      definition = described_class.new(noble_metadata.except('name'))

      expect { definition.name }.to raise_error(Bosh::Clouds::CloudError, /Could not find stemcell name/)
    end
  end

  describe '#identifier' do
    it 'uses the name as offer and the generation as sku' do
      expect(image_definition.identifier).to eq(
        'publisher' => 'bosh',
        'offer' => 'bosh-azure-hyperv-ubuntu-noble-gen2-x64-tls',
        'sku' => 'gen2'
      )
    end
  end

  describe '#properties' do
    it 'describe the operating system, generation, architecture and security type of the stemcell' do
      expect(image_definition.properties).to eq(
        'osType' => 'Linux',
        'hyperVGeneration' => 'V2',
        'architecture' => 'x64',
        'features' => [{ 'name' => 'SecurityType', 'value' => 'TrustedLaunchSupported' }]
      )
    end
  end
end
