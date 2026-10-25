// Lab environment: one VNet, one subnet, two small Linux VMs (web, app).
// Deployed into an existing resource group (rg-azopslab-swc), after monitoring.bicep (it needs the
// action group). Teardown: infra/teardown.sh.
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

@description('VM size. Small sizes only. B-series quota is 0 in Sweden Central (support ticket open), so D2als_v6 is the default; run it only during labs.')
@allowed(['Standard_D2als_v6', 'Standard_B2ts_v2', 'Standard_B2ats_v2', 'Standard_B1s'])
param vmSize string = 'Standard_D2als_v6'

@description('true: outbound through a NAT Gateway and no public IPs on the VMs (see ADR 0002).')
param useNatGateway bool = false

@description('true: Log Analytics, the monitoring agent on both VMs, and the heartbeat and CPU alerts.')
param enableMonitoring bool = true

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
  keepalive: keepalive ? 'true' : 'false' // not string(): ARM turns a bool into 'True'/'False'
}

// The two VMs differ only in purpose and whether HTTP is allowed in.
var vms = [
  { purpose: 'web', allowHttp: true }
  { purpose: 'app', allowHttp: false }
]

// IDs built from known names instead of module outputs, so what-if can preview the VM modules too.
var subnetId = resourceId('Microsoft.Network/virtualNetworks/subnets', 'vnet-${workload}-${regionCode}', 'snet-vms')
var asgSshId = resourceId('Microsoft.Network/applicationSecurityGroups', 'asg-${workload}-ssh-${regionCode}')
var asgWebId = resourceId('Microsoft.Network/applicationSecurityGroups', 'asg-${workload}-web-${regionCode}')
var dcrId = resourceId('Microsoft.Insights/dataCollectionRules', 'dcr-${workload}-vms-${regionCode}')
var vmIds = [for v in vms: resourceId('Microsoft.Compute/virtualMachines', 'vm-${workload}-${v.purpose}-${regionCode}')]
// Created by monitoring.bicep, which must be deployed first.
var actionGroupId = resourceId('Microsoft.Insights/actionGroups', 'ag-${workload}-email')

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

module logs 'modules/vm-logs.bicep' = if (enableMonitoring) {
  name: 'vm-logs'
  params: {
    location: location
    namePrefix: workload
    regionCode: regionCode
    tags: tags
  }
}

module vm 'modules/vm.bicep' = [
  for v in vms: {
    name: 'vm-${v.purpose}'
    dependsOn: [network, logs]
    params: {
      location: location
      name: 'vm-${workload}-${v.purpose}-${regionCode}'
      subnetId: subnetId
      asgIds: v.allowHttp ? [asgSshId, asgWebId] : [asgSshId]
      withPublicIp: !useNatGateway
      vmSize: vmSize
      adminUsername: adminUsername
      sshPublicKey: sshPublicKey
      tags: tags
      dcrId: enableMonitoring ? dcrId : ''
    }
  }
]

module vmAlerts 'modules/vm-alerts.bicep' = if (enableMonitoring) {
  name: 'vm-alerts'
  dependsOn: [vm, logs]
  params: {
    location: location
    namePrefix: workload
    vmIds: vmIds
    workspaceId: resourceId('Microsoft.OperationalInsights/workspaces', 'law-${workload}-${regionCode}')
    actionGroupId: actionGroupId
    tags: tags
  }
}

output vmNames array = [for (v, i) in vms: vm[i].outputs.name]
output publicIps array = [for (v, i) in vms: vm[i].outputs.publicIp]
