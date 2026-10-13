// Lab environment: one VNet, one subnet, two small Linux VMs (web, app).
// Deployed into an existing resource group (rg-azopslab-swc). Teardown = delete the resource group.
targetScope = 'resourceGroup'

@description('Azure region. The lab is limited to Sweden Central.')
@allowed(['swedencentral'])
param location string = 'swedencentral'

@description('Your public IP in CIDR form (x.x.x.x/32). Only this address may reach SSH and HTTP.')
param adminSourceIp string

@description('SSH public key for the admin user. Password login is disabled.')
@secure()
param sshPublicKey string

@description('Admin user name on both VMs.')
param adminUsername string = 'azureops'

@description('VM size. Small B-series only, to keep cost low.')
@allowed(['Standard_B2ats_v2', 'Standard_B1s'])
param vmSize string = 'Standard_B2ats_v2'

@description('true: outbound through a NAT Gateway and no public IPs on the VMs (see ADR 0002).')
param useNatGateway bool = false

@description('Tag: who owns these resources.')
param owner string

@description('Tag: date (YYYY-MM-DD) after which the resources may be deleted.')
param expires string

@description('Tag: true keeps the resources past the expires date.')
param keepalive bool = false

var workload = 'azopslab'
var regionCode = 'swc'
var tags = {
  owner: owner
  env: 'lab'
  project: 'azure-ops-lab'
  expires: expires
  keepalive: string(keepalive)
}

// The two VMs differ only in purpose and whether HTTP is allowed in.
var vms = [
  { purpose: 'web', allowHttp: true }
  { purpose: 'app', allowHttp: false }
]

module network 'modules/network.bicep' = {
  name: 'network'
  params: {
    location: location
    namePrefix: workload
    regionCode: regionCode
    adminSourceIp: adminSourceIp
    useNatGateway: useNatGateway
    tags: tags
  }
}

module vm 'modules/vm.bicep' = [
  for v in vms: {
    name: 'vm-${v.purpose}'
    params: {
      location: location
      name: 'vm-${workload}-${v.purpose}-${regionCode}'
      subnetId: network.outputs.subnetId
      asgIds: v.allowHttp ? [network.outputs.asgSshId, network.outputs.asgWebId] : [network.outputs.asgSshId]
      withPublicIp: !useNatGateway
      vmSize: vmSize
      adminUsername: adminUsername
      sshPublicKey: sshPublicKey
      tags: tags
    }
  }
]

output vmNames array = [for (v, i) in vms: vm[i].outputs.name]
output publicIps array = [for (v, i) in vms: vm[i].outputs.publicIp]
