# frozen_string_literal: true

require 'spec_helper'
require 'unit/vm_manager/create/shared_stuff'

describe Bosh::AzureCloud::VMManager, '#_create_network_interfaces — dual-stack' do
  include_context 'shared stuff for vm manager'

  subject(:vm_manager_ds) { vm_manager2 }

  let(:manual_network_v4) { instance_double(Bosh::AzureCloud::ManualNetwork) }
  let(:manual_network_v6) { instance_double(Bosh::AzureCloud::ManualNetwork) } # same nic_group, same NIC
  let(:dynamic_network) { instance_double(Bosh::AzureCloud::DynamicNetwork) } # different nic_group, separate NIC
  let(:dual_stack_subnet) { double('dual-stack-subnet', id: 'fake-dual-stack-subnet-id') }

  before do
    allow(manual_network_v4).to receive(:is_a?) { |klass| klass == Bosh::AzureCloud::ManualNetwork }
    allow(manual_network_v4).to receive(:resource_group_name).and_return(MOCK_RESOURCE_GROUP_NAME)
    allow(manual_network_v4).to receive(:virtual_network_name).and_return('fake-virtual-network-name')
    allow(manual_network_v4).to receive(:subnet_name).and_return('dual-stack-subnet')
    allow(manual_network_v4).to receive(:private_ip).and_return('10.0.0.5')
    allow(manual_network_v4).to receive(:security_group).and_return(empty_security_group)
    allow(manual_network_v4).to receive(:application_security_groups).and_return([])
    allow(manual_network_v4).to receive(:ip_forwarding).and_return(false)
    allow(manual_network_v4).to receive(:accelerated_networking).and_return(false)

    allow(manual_network_v6).to receive(:is_a?) { |klass| klass == Bosh::AzureCloud::ManualNetwork }
    allow(manual_network_v6).to receive(:resource_group_name).and_return(MOCK_RESOURCE_GROUP_NAME)
    allow(manual_network_v6).to receive(:virtual_network_name).and_return('fake-virtual-network-name')
    allow(manual_network_v6).to receive(:subnet_name).and_return('dual-stack-subnet')
    allow(manual_network_v6).to receive(:private_ip).and_return('fd00::5')
    allow(manual_network_v6).to receive(:security_group).and_return(empty_security_group)
    allow(manual_network_v6).to receive(:application_security_groups).and_return([])
    allow(manual_network_v6).to receive(:ip_forwarding).and_return(false)
    allow(manual_network_v6).to receive(:accelerated_networking).and_return(false)

    allow(dynamic_network).to receive(:resource_group_name).and_return(MOCK_RESOURCE_GROUP_NAME)
    allow(dynamic_network).to receive(:virtual_network_name).and_return('fake-virtual-network-name')
    allow(dynamic_network).to receive(:subnet_name).and_return('fake-subnet-name')
    allow(dynamic_network).to receive(:security_group).and_return(empty_security_group)
    allow(dynamic_network).to receive(:application_security_groups).and_return([])
    allow(dynamic_network).to receive(:ip_forwarding).and_return(false)
    allow(dynamic_network).to receive(:accelerated_networking).and_return(false)

    allow(azure_client).to receive(:get_network_subnet_by_name)
      .with(MOCK_RESOURCE_GROUP_NAME, 'fake-virtual-network-name', 'dual-stack-subnet')
      .and_return(dual_stack_subnet)

    allow(azure_client).to receive(:get_network_subnet_by_name)
      .with(MOCK_RESOURCE_GROUP_NAME, 'fake-virtual-network-name', 'fake-subnet-name')
      .and_return(subnet)

    allow(network_configurator).to receive(:vip_network).and_return(nil)
    allow(azure_client).to receive(:list_public_ips).and_return([])
  end

  context 'dual-stack via nic_group: two manual networks (IPv4 + IPv6) with same nic_group' do
    before do
      allow(network_configurator).to receive(:nic_groups)
        .and_return([[manual_network_v4, manual_network_v6]])
    end

    it 'should create exactly one NIC' do
      expect(azure_client).to receive(:create_network_interface).once
      expect(azure_client).to receive(:get_network_interface_by_name).once

      vm_manager_ds.send(:_create_network_interfaces,
                         MOCK_RESOURCE_GROUP_NAME, vm_name, location,
                         vm_props, network_configurator)
    end

    it 'should pass two ip_configurations to create_network_interface' do
      expect(azure_client).to receive(:create_network_interface) do |_rg, nic_params|
        expect(nic_params[:ip_configurations].length).to eq(2)
      end

      vm_manager_ds.send(:_create_network_interfaces,
                         MOCK_RESOURCE_GROUP_NAME, vm_name, location,
                         vm_props, network_configurator)
    end

    it 'should set IPv4 on the first ipconfig and IPv6 on the second' do
      expect(azure_client).to receive(:create_network_interface) do |_rg, nic_params|
        ipconfigs = nic_params[:ip_configurations]

        expect(ipconfigs[0][:ip_version]).to eq('IPv4')
        expect(ipconfigs[0][:private_ip]).to eq('10.0.0.5')
        expect(ipconfigs[0][:name]).to eq('ipconfig0-0')

        expect(ipconfigs[1][:ip_version]).to eq('IPv6')
        expect(ipconfigs[1][:private_ip]).to eq('fd00::5')
        expect(ipconfigs[1][:name]).to eq('ipconfig0-1')
      end

      vm_manager_ds.send(:_create_network_interfaces,
                         MOCK_RESOURCE_GROUP_NAME, vm_name, location,
                         vm_props, network_configurator)
    end

    it 'should use the same subnet for both ipConfigurations' do
      expect(azure_client).to receive(:create_network_interface) do |_rg, nic_params|
        ipconfigs = nic_params[:ip_configurations]
        expect(ipconfigs[0][:subnet]).to eq(dual_stack_subnet)
        expect(ipconfigs[1][:subnet]).to eq(dual_stack_subnet)
      end

      vm_manager_ds.send(:_create_network_interfaces,
                         MOCK_RESOURCE_GROUP_NAME, vm_name, location,
                         vm_props, network_configurator)
    end

    it 'should name the NIC as vm_name-0' do
      expect(azure_client).to receive(:create_network_interface) do |_rg, nic_params|
        expect(nic_params[:name]).to eq("#{vm_name}-0")
      end

      vm_manager_ds.send(:_create_network_interfaces,
                         MOCK_RESOURCE_GROUP_NAME, vm_name, location,
                         vm_props, network_configurator)
    end
  end

  context 'multiple nic_groups with dual-stack on first NIC' do
    before do
      allow(network_configurator).to receive(:nic_groups)
        .and_return([[manual_network_v4, manual_network_v6], [dynamic_network]])
    end

    it 'should create two NICs' do
      expect(azure_client).to receive(:create_network_interface).twice
      expect(azure_client).to receive(:get_network_interface_by_name).twice

      vm_manager_ds.send(:_create_network_interfaces,
                         MOCK_RESOURCE_GROUP_NAME, vm_name, location,
                         vm_props, network_configurator)
    end

    it 'should create first NIC with 2 ipConfigurations and second NIC with 1' do
      nic_params_list = []
      allow(azure_client).to receive(:create_network_interface) do |_rg, nic_params|
        nic_params_list << nic_params
      end

      vm_manager_ds.send(:_create_network_interfaces,
                         MOCK_RESOURCE_GROUP_NAME, vm_name, location,
                         vm_props, network_configurator)

      expect(nic_params_list[0][:ip_configurations].length).to eq(2)
      expect(nic_params_list[1][:ip_configurations].length).to eq(1)
    end

    it 'should attach load balancers and application gateways only to the first NIC' do
      nic_params_list = []
      allow(azure_client).to receive(:create_network_interface) do |_rg, nic_params|
        nic_params_list << nic_params
      end

      vm_manager_ds.send(:_create_network_interfaces,
                         MOCK_RESOURCE_GROUP_NAME, vm_name, location,
                         vm_props, network_configurator)

      # First NIC (primary) gets LB and AGW
      expect(nic_params_list[0][:load_balancers]).not_to be_nil
      expect(nic_params_list[0][:application_gateways]).not_to be_nil

      # Second NIC (secondary) does not
      expect(nic_params_list[1][:load_balancers]).to be_nil
      expect(nic_params_list[1][:application_gateways]).to be_nil
    end

    it 'should name NICs as vm_name-0 and vm_name-1' do
      nic_params_list = []
      allow(azure_client).to receive(:create_network_interface) do |_rg, nic_params|
        nic_params_list << nic_params
      end

      vm_manager_ds.send(:_create_network_interfaces,
                         MOCK_RESOURCE_GROUP_NAME, vm_name, location,
                         vm_props, network_configurator)

      expect(nic_params_list[0][:name]).to eq("#{vm_name}-0")
      expect(nic_params_list[1][:name]).to eq("#{vm_name}-1")
    end
  end

  context 'single-stack IPv4 regression: one manual network, no nic_group' do
    before do
      # Single network in its own nic_group (the default when nic_group is not set)
      allow(network_configurator).to receive(:nic_groups)
        .and_return([[manual_network], [dynamic_network]])
    end

    it 'should create one NIC per network, each with 1 ipConfiguration' do
      nic_params_list = []
      allow(azure_client).to receive(:create_network_interface) do |_rg, nic_params|
        nic_params_list << nic_params
      end

      vm_manager_ds.send(:_create_network_interfaces,
                         MOCK_RESOURCE_GROUP_NAME, vm_name, location,
                         vm_props, network_configurator)

      expect(nic_params_list.length).to eq(2)
      expect(nic_params_list[0][:ip_configurations].length).to eq(1)
      expect(nic_params_list[1][:ip_configurations].length).to eq(1)
    end

    it 'should set ip_version=IPv4 on manual network ipConfig' do
      nic_params_list = []
      allow(azure_client).to receive(:create_network_interface) do |_rg, nic_params|
        nic_params_list << nic_params
      end

      vm_manager_ds.send(:_create_network_interfaces,
                         MOCK_RESOURCE_GROUP_NAME, vm_name, location,
                         vm_props, network_configurator)

      expect(nic_params_list[0][:ip_configurations][0][:ip_version]).to eq('IPv4')
      expect(nic_params_list[0][:ip_configurations][0][:private_ip]).to eq('private-ip')
    end
  end

  context '_detect_ip_version' do
    it 'should return IPv6 for an IPv6 manual network' do
      result = vm_manager_ds.send(:_detect_ip_version, manual_network_v6)
      expect(result).to eq('IPv6')
    end

    it 'should return IPv4 for an IPv4 manual network' do
      result = vm_manager_ds.send(:_detect_ip_version, manual_network_v4)
      expect(result).to eq('IPv4')
    end

    it 'should default to IPv4 for a dynamic network' do
      result = vm_manager_ds.send(:_detect_ip_version, dynamic_network)
      expect(result).to eq('IPv4')
    end
  end
end

describe Bosh::AzureCloud::VMManager, '#_build_nic_groups_to_iface' do
  let(:logger) { Logger.new('/dev/null') }
  let(:azure_config) do
    instance_double(Bosh::AzureCloud::AzureConfig, use_managed_disks: true)
  end
  let(:disk_manager) { instance_double(Bosh::AzureCloud::DiskManager2) }
  let(:disk_manager2) { instance_double(Bosh::AzureCloud::DiskManager2) }
  let(:azure_client) { instance_double(Bosh::AzureCloud::AzureClient) }
  let(:storage_account_manager) { instance_double(Bosh::AzureCloud::StorageAccountManager) }
  let(:stemcell_manager) { instance_double(Bosh::AzureCloud::StemcellManager) }
  let(:stemcell_manager2) { instance_double(Bosh::AzureCloud::StemcellManager2) }
  let(:light_stemcell_manager) { instance_double(Bosh::AzureCloud::LightStemcellManager) }

  before do
    allow(Bosh::Clouds::Config).to receive(:logger).and_return(logger)
  end

  subject(:vm_manager) do
    Bosh::AzureCloud::VMManager.new(
      azure_config,
      disk_manager, disk_manager2,
      azure_client, storage_account_manager,
      stemcell_manager, stemcell_manager2, light_stemcell_manager
    )
  end

  let(:network_configurator) { instance_double(Bosh::AzureCloud::NetworkConfigurator) }

  context 'dual-stack with explicit nic_group (single NIC)' do
    let(:net_v4) do
      instance_double(Bosh::AzureCloud::ManualNetwork).tap do |n|
        allow(n).to receive(:spec).and_return({ 'nic_group' => '1', 'type' => 'manual', 'ip' => '10.0.0.5' })
      end
    end
    let(:net_v6) do
      instance_double(Bosh::AzureCloud::ManualNetwork).tap do |n|
        allow(n).to receive(:spec).and_return({ 'nic_group' => '1', 'type' => 'manual', 'ip' => 'fd00::5' })
      end
    end

    before do
      allow(network_configurator).to receive(:nic_groups).and_return([[net_v4, net_v6]])
    end

    it 'returns a mapping from nic_group to eth interface' do
      result = vm_manager.send(:_build_nic_groups_to_iface, network_configurator)
      expect(result).to eq({ '1' => 'eth0' })
    end
  end

  context 'multi-NIC dual-stack (two nic_groups)' do
    let(:net_v4_a) do
      instance_double(Bosh::AzureCloud::ManualNetwork).tap do |n|
        allow(n).to receive(:spec).and_return({ 'nic_group' => '1', 'type' => 'manual', 'ip' => '10.0.0.5' })
      end
    end
    let(:net_v6_a) do
      instance_double(Bosh::AzureCloud::ManualNetwork).tap do |n|
        allow(n).to receive(:spec).and_return({ 'nic_group' => '1', 'type' => 'manual', 'ip' => 'fd00::5' })
      end
    end
    let(:net_v4_b) do
      instance_double(Bosh::AzureCloud::ManualNetwork).tap do |n|
        allow(n).to receive(:spec).and_return({ 'nic_group' => '2', 'type' => 'manual', 'ip' => '10.0.1.5' })
      end
    end
    let(:net_v6_b) do
      instance_double(Bosh::AzureCloud::ManualNetwork).tap do |n|
        allow(n).to receive(:spec).and_return({ 'nic_group' => '2', 'type' => 'manual', 'ip' => 'fd01::5' })
      end
    end

    before do
      allow(network_configurator).to receive(:nic_groups).and_return([[net_v4_a, net_v6_a], [net_v4_b, net_v6_b]])
    end

    it 'returns eth0 for group 1 and eth1 for group 2' do
      result = vm_manager.send(:_build_nic_groups_to_iface, network_configurator)
      expect(result).to eq({ '1' => 'eth0', '2' => 'eth1' })
    end
  end

  context 'single-stack without explicit nic_group (backward compat)' do
    let(:net_single) do
      instance_double(Bosh::AzureCloud::ManualNetwork).tap do |n|
        allow(n).to receive(:spec).and_return({ 'type' => 'manual', 'ip' => '10.0.0.5' })
      end
    end

    before do
      allow(network_configurator).to receive(:nic_groups).and_return([[net_single]])
    end

    it 'returns an empty hash' do
      result = vm_manager.send(:_build_nic_groups_to_iface, network_configurator)
      expect(result).to eq({})
    end
  end

  context 'mixed: dual-stack NIC plus single-stack NIC' do
    let(:net_v4_dual) do
      instance_double(Bosh::AzureCloud::ManualNetwork).tap do |n|
        allow(n).to receive(:spec).and_return({ 'nic_group' => '1', 'type' => 'manual', 'ip' => '10.0.0.5' })
      end
    end
    let(:net_v6_dual) do
      instance_double(Bosh::AzureCloud::ManualNetwork).tap do |n|
        allow(n).to receive(:spec).and_return({ 'nic_group' => '1', 'type' => 'manual', 'ip' => 'fd00::5' })
      end
    end
    let(:net_single) do
      instance_double(Bosh::AzureCloud::ManualNetwork).tap do |n|
        allow(n).to receive(:spec).and_return({ 'type' => 'manual', 'ip' => '10.0.1.5' })
      end
    end

    before do
      allow(network_configurator).to receive(:nic_groups).and_return([[net_v4_dual, net_v6_dual], [net_single]])
    end

    it 'maps only the dual-stack group' do
      result = vm_manager.send(:_build_nic_groups_to_iface, network_configurator)
      expect(result).to eq({ '1' => 'eth0' })
    end
  end
end
