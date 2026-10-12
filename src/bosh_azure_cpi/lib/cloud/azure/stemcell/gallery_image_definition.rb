# frozen_string_literal: true

require 'digest'

module Bosh::AzureCloud
  # Describes the Azure Compute Gallery image definition for the image versions of a stemcell.
  #
  # Generation, architecture and security type can't be changed once an image definition exists. They are part of
  # the name, so that stemcells of a series which differ in any of them never share an image definition, e.g.
  # 'bosh-azure-hyperv-ubuntu-noble-gen2-x64-tls' and 'bosh-azure-hyperv-ubuntu-noble-gen2-arm64-tls'.
  #
  # Older CPI versions named image definitions '<series>' or '<series>-gen2'. Stemcells uploaded into them keep
  # using them, because the image definition of a stemcell is recorded in its metadata.
  class GalleryImageDefinition
    include Helpers

    PUBLISHER = 'bosh'
    DEFAULT_GENERATION = 'gen1'
    MAX_NAME_LENGTH = 64
    SERIES_DIGEST_LENGTH = 8
    SECURITY_TYPE_ABBREVIATIONS = {
      'Standard' => 'std',
      'TrustedLaunch' => 'tl',
      'TrustedLaunchSupported' => 'tls',
      'ConfidentialVM' => 'cvm',
      'ConfidentialVMSupported' => 'cvms',
      'TrustedLaunchAndConfidentialVmSupported' => 'tlcvms'
    }.freeze

    # @param [Hash] stemcell_metadata - the cloud properties of the stemcell
    def initialize(stemcell_metadata)
      @metadata = stemcell_metadata
      @logger = Bosh::Clouds::Config.logger
    end

    # @return [String] '<series>-<generation>-<architecture>[-<security type>]'
    def name
      series = @metadata['name']
      cloud_error('Could not find stemcell name in metadata.') if series.nil?

      suffix = [generation, architecture.downcase, security_type_abbreviation].compact.join('-')
      full_name = "#{series}-#{suffix}"
      return full_name if full_name.length <= MAX_NAME_LENGTH

      # Shorten the series, but keep the name unique by adding a digest of the full series.
      tail = "-#{Digest::SHA256.hexdigest(series)[0, SERIES_DIGEST_LENGTH]}-#{suffix}"
      "#{series[0, MAX_NAME_LENGTH - tail.length]}#{tail}"
    end

    # @return [Hash] publisher, offer and sku, which must be unique within a gallery
    def identifier
      { 'publisher' => PUBLISHER, 'offer' => name, 'sku' => generation }
    end

    # @return [Hash] the immutable properties of the image definition
    def properties
      {
        'osType' => os_type,
        'hyperVGeneration' => "V#{generation.delete_prefix('gen')}",
        'architecture' => architecture,
        'features' => features
      }.compact
    end

    private

    def generation
      (@metadata['generation'] || DEFAULT_GENERATION).downcase
    end

    def gen1?
      generation == DEFAULT_GENERATION
    end

    def architecture
      CpuArchitecture.normalize(@metadata['architecture']) || CpuArchitecture::X64
    end

    # Security types require generation 2.
    def security_type
      @metadata['security_type'] unless gen1?
    end

    def security_type_abbreviation
      return nil if security_type.nil?

      abbreviation = SECURITY_TYPE_ABBREVIATIONS.find { |type, _| type.casecmp?(security_type) }&.last
      cloud_error("Unsupported security_type '#{security_type}'. Supported values: #{SECURITY_TYPE_ABBREVIATIONS.keys.join(', ')}") if abbreviation.nil?

      abbreviation
    end

    def os_type
      normalized_os_type = @metadata['os_type']&.downcase&.capitalize
      cloud_error("Invalid os_type '#{@metadata['os_type']}'. Must be either 'Linux' or 'Windows'") unless ['Linux', 'Windows'].include?(normalized_os_type)

      normalized_os_type
    end

    def features
      return nil if gen1?

      result = []

      if @metadata.key?('disk_controller_types')
        disk_controllers = @metadata['disk_controller_types']
        if disk_controllers.is_a?(Array) && !disk_controllers.empty?
          result << { 'name' => 'DiskControllerTypes', 'value' => normalize_disk_controllers(disk_controllers).join(',') }
        else
          @logger.warn("Ignoring invalid 'disk_controller_types' metadata: #{disk_controllers}")
        end
      end

      if @metadata.key?('accelerated_networking')
        result << { 'name' => 'IsAcceleratedNetworkSupported', 'value' => @metadata['accelerated_networking'] ? 'True' : 'False' }
      end

      if @metadata.key?('hibernation')
        result << { 'name' => 'IsHibernateSupported', 'value' => @metadata['hibernation'] ? 'True' : 'False' }
      end

      result << { 'name' => 'SecurityType', 'value' => security_type } unless security_type.nil?

      result.empty? ? nil : result
    end

    def normalize_disk_controllers(disk_controllers)
      disk_controllers.map do |controller|
        case controller.to_s.downcase
        when 'scsi'
          'SCSI'
        when 'nvme'
          'NVMe'
        else
          controller
        end
      end
    end
  end
end
