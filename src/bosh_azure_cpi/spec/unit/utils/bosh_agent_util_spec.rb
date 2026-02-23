# frozen_string_literal: true

require 'spec_helper'

describe Bosh::AzureCloud::BoshAgentUtil do
  subject(:agent_util) { Bosh::AzureCloud::BoshAgentUtil.new }

  let(:instance_id) { 'fake-instance-id' }
  let(:dns) { 'fake-dns' }
  let(:agent_id) { 'fake-agent-id' }
  let(:vm_params) do
    {
      name: 'vm_name',
      ephemeral_disk: {},
    }
  end
  let(:network_spec) do
    {
      'network_a' => {
        'type' => 'dynamic',
        'cloud_properties' => {
          'virtual_network_name' => 'vnet_name',
          'subnet_name' => 'subnet_name'
        }
      }
    }
  end
  let(:environment) { 'fake-agent-environment' }
  let(:config) { instance_double(Bosh::AzureCloud::Config) }
  let(:computer_name) { 'fake-computer-name' }

  before do
    allow(config).to receive(:agent).and_return({ 'mbus' => 'http://u:p@somewhere' })
  end

  describe '#user_data_obj' do
    let(:expected_user_data) do
      {
        server: { name: instance_id },
        dns: { nameserver: dns },
        'vm' => { 'name' => vm_params[:name] },
        'agent_id' => agent_id,
        'networks' => {
          'network_a' => {
            'type' => 'dynamic',
            'cloud_properties' => {
              'virtual_network_name' => 'vnet_name',
              'subnet_name' => 'subnet_name'
            },
            'use_dhcp' => true
          }
        },
        'disks' => {
          'system' => '/dev/sda',
          'persistent' => {},
          'ephemeral' => {
            'lun' => '0',
            'host_device_id' => '{f8b3781b-1e82-4818-a1c3-63d806ec15bb}',
          }
        },
        'env' => environment,
        'mbus' => 'http://u:p@somewhere',
      }
    end

    it 'combines the reduced vm metadata with agent settings' do
      user_data = agent_util.user_data_obj(
        instance_id,
        dns,
        agent_id,
        network_spec,
        environment,
        vm_params,
        config,
      )

      expect(user_data).to eq(expected_user_data)
    end
  end

  describe '#_agent_network_spec (dual-stack alias)' do
    context 'when nic_groups_to_iface is provided (dual-stack)' do
      let(:nic_groups_to_iface) { { '1' => 'eth0' } }

      let(:network_spec) do
        {
          'default-ipv4' => {
            'type' => 'manual',
            'ip' => '10.0.0.5',
            'nic_group' => '1',
            'default' => %w[dns gateway],
            'cloud_properties' => {
              'virtual_network_name' => 'boshvnet',
              'subnet_name' => 'dual-stack-subnet'
            }
          },
          'default-ipv6' => {
            'type' => 'manual',
            'ip' => 'fd00::5',
            'nic_group' => '1',
            'cloud_properties' => {
              'virtual_network_name' => 'boshvnet',
              'subnet_name' => 'dual-stack-subnet'
            }
          }
        }
      end

      it 'should set alias on both networks sharing the same nic_group' do
        result = agent_util.send(:_agent_network_spec, network_spec, nic_groups_to_iface)

        expect(result['default-ipv4']['alias']).to eq('eth0')
        expect(result['default-ipv6']['alias']).to eq('eth0')
      end

      it 'should still set use_dhcp on all networks' do
        result = agent_util.send(:_agent_network_spec, network_spec, nic_groups_to_iface)

        expect(result['default-ipv4']['use_dhcp']).to be true
        expect(result['default-ipv6']['use_dhcp']).to be true
      end

      it 'should preserve all other network spec fields' do
        result = agent_util.send(:_agent_network_spec, network_spec, nic_groups_to_iface)

        expect(result['default-ipv4']['ip']).to eq('10.0.0.5')
        expect(result['default-ipv4']['type']).to eq('manual')
        expect(result['default-ipv6']['ip']).to eq('fd00::5')
      end
    end

    context 'when nic_groups_to_iface has multiple groups (multi-NIC dual-stack)' do
      let(:nic_groups_to_iface) { { '1' => 'eth0', '2' => 'eth1' } }

      let(:network_spec) do
        {
          'net-v4-a' => {
            'type' => 'manual',
            'ip' => '10.0.0.5',
            'nic_group' => '1',
            'default' => %w[dns gateway],
            'cloud_properties' => {}
          },
          'net-v6-a' => {
            'type' => 'manual',
            'ip' => 'fd00::5',
            'nic_group' => '1',
            'cloud_properties' => {}
          },
          'net-v4-b' => {
            'type' => 'manual',
            'ip' => '10.0.1.5',
            'nic_group' => '2',
            'cloud_properties' => {}
          },
          'net-v6-b' => {
            'type' => 'manual',
            'ip' => 'fd01::5',
            'nic_group' => '2',
            'cloud_properties' => {}
          }
        }
      end

      it 'should set alias eth0 for group 1 and eth1 for group 2' do
        result = agent_util.send(:_agent_network_spec, network_spec, nic_groups_to_iface)

        expect(result['net-v4-a']['alias']).to eq('eth0')
        expect(result['net-v6-a']['alias']).to eq('eth0')
        expect(result['net-v4-b']['alias']).to eq('eth1')
        expect(result['net-v6-b']['alias']).to eq('eth1')
      end
    end

    context 'when no nic_group in network spec (single-stack backward compatibility)' do
      it 'should NOT set alias when nic_groups_to_iface is empty' do
        result = agent_util.send(:_agent_network_spec, network_spec, {})

        expect(result['network_a']).not_to have_key('alias')
      end

      it 'should NOT set alias when nic_groups_to_iface is not passed' do
        result = agent_util.send(:_agent_network_spec, network_spec)

        expect(result['network_a']).not_to have_key('alias')
      end

      it 'should still set use_dhcp' do
        result = agent_util.send(:_agent_network_spec, network_spec)

        expect(result['network_a']['use_dhcp']).to be true
      end
    end

    context 'when nic_group is present on some networks but not others' do
      let(:nic_groups_to_iface) { { '1' => 'eth0' } }

      let(:network_spec) do
        {
          'grouped-v4' => {
            'type' => 'manual',
            'ip' => '10.0.0.5',
            'nic_group' => '1',
            'cloud_properties' => {}
          },
          'grouped-v6' => {
            'type' => 'manual',
            'ip' => 'fd00::5',
            'nic_group' => '1',
            'cloud_properties' => {}
          },
          'ungrouped' => {
            'type' => 'dynamic',
            'cloud_properties' => {}
          }
        }
      end

      it 'should set alias only on networks with nic_group' do
        result = agent_util.send(:_agent_network_spec, network_spec, nic_groups_to_iface)

        expect(result['grouped-v4']['alias']).to eq('eth0')
        expect(result['grouped-v6']['alias']).to eq('eth0')
        expect(result['ungrouped']).not_to have_key('alias')
      end
    end
  end

  describe '#user_data_obj — dual-stack alias threading' do
    context 'when nic_groups_to_iface is passed' do
      let(:nic_groups_to_iface) { { '1' => 'eth0' } }

      let(:network_spec) do
        {
          'default-ipv4' => {
            'type' => 'manual',
            'ip' => '10.0.0.5',
            'nic_group' => '1',
            'cloud_properties' => {}
          },
          'default-ipv6' => {
            'type' => 'manual',
            'ip' => 'fd00::5',
            'nic_group' => '1',
            'cloud_properties' => {}
          }
        }
      end

      it 'should include alias in the agent network settings' do
        user_data = agent_util.user_data_obj(
          instance_id, dns, agent_id, network_spec, environment, vm_params, config, nil, nic_groups_to_iface
        )

        networks = user_data['networks']
        expect(networks['default-ipv4']['alias']).to eq('eth0')
        expect(networks['default-ipv6']['alias']).to eq('eth0')
      end
    end

    context 'when nic_groups_to_iface is not passed (backward compat)' do
      it 'should not include alias in agent network settings' do
        user_data = agent_util.user_data_obj(
          instance_id, dns, agent_id, network_spec, environment, vm_params, config
        )

        networks = user_data['networks']
        expect(networks['network_a']).not_to have_key('alias')
      end
    end
  end
end
