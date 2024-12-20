# frozen_string_literal: true

module Bosh::AzureCloud
  class LightStemcellManager
    include Bosh::Exec
    include Helpers

    def initialize(blob_manager, storage_account_manager, azure_client)
      @blob_manager = blob_manager
      @storage_account_manager = storage_account_manager
      @azure_client = azure_client
      @logger = Bosh::Clouds::Config.logger

      default_storage_account = @storage_account_manager.default_storage_account
      @default_storage_account_name = default_storage_account[:name]
      @default_location = default_storage_account[:location]
    end

    # Deletes a stemcell.
    #
    # @param name [String] The name of the stemcell to delete.
    def delete_stemcell(name)
      @logger.info("delete_stemcell(#{name})")
      metadata = _get_metadata(name)
      @blob_manager.delete_blob(@default_storage_account_name, STEMCELL_CONTAINER, "#{name}.vhd") unless metadata.nil?
    end

    # Creates a new light stemcell.
    #
    # @param stemcell_properties [Hash] The properties of the stemcell.
    # @option stemcell_properties [Hash] :image The image property of the stemcell.
    #   The image property can have one of the following structures:
    #   1. For platform images:
    #     {
    #       'publisher' => 'publisher_name',
    #       'offer' => 'offer_name',
    #       'sku' => 'sku_name',
    #       'version' => 'version_number'
    #     }
    #   2. For compute gallery images:
    #     {
    #       'gallery' => 'gallery_name',
    #       'definition' => 'gallery_image_name',
    #       'version' => 'version_number',
    #       'resource_group' => 'resource_group_name'
    #     }
    # @return [String] The name of the created stemcell.
    # @raise [Bosh::Clouds::CloudError] if the image property of the stemcell is invalid.
    def create_stemcell(stemcell_properties)
      @logger.info("create_stemcell(#{stemcell_properties})")
      cloud_error("Cannot find the light stemcell (#{stemcell_properties['image']}) in the location '#{@default_location}'") unless _platform_image?(@default_location, stemcell_properties)

      stemcell_name = "#{LIGHT_STEMCELL_PREFIX}-#{SecureRandom.uuid}"
      @logger.info("Uploading metadata for the light stemcell '#{stemcell_name}' into the storage account '#{@default_storage_account_name}'")
      metadata = stemcell_properties.dup
      metadata['image'] = JSON.dump(metadata['image'])
      @blob_manager.create_empty_page_blob(@default_storage_account_name, STEMCELL_CONTAINER, "#{stemcell_name}.vhd", 1, metadata)
      stemcell_name
    end

    # Checks if a stemcell exists.
    # The stemcell can be in the default storage account or in a different storage account.
    #
    # @param location [String] The location of the stemcell.
    # @param name [String] The name of the stemcell.
    # @return [Boolean] True if the stemcell exists; false otherwise.
    # @raise [Bosh::Clouds::CloudError] if the image property of the stemcell is invalid.
    def has_stemcell?(location, name)
      @logger.info("has_stemcell?(#{location}, #{name})")
      metadata = _get_metadata(name)
      return false if metadata.nil?

      _platform_image?(location, metadata)
    end

    # Gets information about a stemcell.
    #
    # @param name [String] The name of the stemcell.
    # @return [StemcellInfo] The information about the stemcell.
    # @raise [Bosh::Clouds::CloudError] if the stemcell does not exist.
    def get_stemcell_info(name)
      @logger.info("get_stemcell_info(#{name})")
      metadata = _get_metadata(name)
      cloud_error("The light stemcell '#{name}' does not exist in the storage account '#{@default_storage_account_name}'") if metadata.nil?

      version = _platform_image(@default_location, metadata)
      StemcellInfo.new(version[:id], metadata) # This should also work for the be done with the platform image > TODO: validate.
    end

    private

    def _get_metadata(name)
      metadata = @blob_manager.get_blob_metadata(@default_storage_account_name, STEMCELL_CONTAINER, "#{name}.vhd")
      return nil if metadata.nil?

      metadata['image'] = JSON.parse(metadata['image'], symbolize_keys: false)
      metadata
    end

    def _platform_image?(location, stemcell_properties)
      !_platform_image(location, stemcell_properties).nil?
    end

    def _platform_image(location, stemcell_properties)
      stemcell_info = StemcellInfo.new('', stemcell_properties)

      raise Bosh::Clouds::CloudError, "The image property of the stemcell is invalid. It should contain a 'version' key" unless stemcell_info.image.key?('version')

      versions = []
      if stemcell_info.is_platform_image?
        @logger.debug("list_platform_image_versions(#{location}, #{stemcell_info.image['publisher']}, #{stemcell_info.image['offer']}, #{stemcell_info.image['sku']})")
        versions = @azure_client.list_platform_image_versions(
          location,
          stemcell_info.image['publisher'],
          stemcell_info.image['offer'],
          stemcell_info.image['sku']
        )
      elsif stemcell_info.is_compute_gallery_image?
        @logger.debug("list_compute_gallery_image_versions(#{location}, #{stemcell_info.image['gallery']}, #{stemcell_info.image['definition']}, #{stemcell_info.image['version']})")
        versions = @azure_client.list_compute_gallery_image_versions(
          location,
          stemcell_info.image['gallery'],
          stemcell_info.image['definition']
        )
      else
        cloud_error("The image property of the stemcell is invalid. It should contain either 'publisher, offer, sku' or 'gallery_name, gallery_image_name'")
      end

      version = versions.find { |v| v[:name] == stemcell_info.image['version'] }
      if version.nil?
        @logger.debug("_platform_image - The version '#{image_version}' of the image is not found")
      else
        @logger.debug("_platform_image - The version '#{image_version}' of the image is not in the location '#{location}'") if version[:location] != location
      end

      version
    end
  end
end
