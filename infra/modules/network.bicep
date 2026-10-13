// VNet with one subnet, an NSG that only admits the admin IP, and an optional NAT Gateway.

param location string
param namePrefix string
param regionCode string
param adminSourceIp string
param useNatGateway bool
param tags object

// Application security groups let NSG rules target "web VMs" instead of fixed IPs.
resource asgSsh 'Microsoft.Network/applicationSecurityGroups@2024-05-01' = {
  name: 'asg-${namePrefix}-ssh-${regionCode}'
  location: location
  tags: tags
}

resource asgWeb 'Microsoft.Network/applicationSecurityGroups@2024-05-01' = {
  name: 'asg-${namePrefix}-web-${regionCode}'
  location: location
  tags: tags
}

resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-${namePrefix}-vms-${regionCode}'
  location: location
  tags: tags
  properties: {
    // Anything not allowed here is blocked by the built-in DenyAllInBound rule.
    securityRules: [
      {
        name: 'Allow-SSH-From-Admin'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: adminSourceIp
          sourcePortRange: '*'
          destinationApplicationSecurityGroups: [{ id: asgSsh.id }]
          destinationPortRange: '22'
        }
      }
      {
        name: 'Allow-HTTP-From-Admin'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: adminSourceIp
          sourcePortRange: '*'
          destinationApplicationSecurityGroups: [{ id: asgWeb.id }]
          destinationPortRange: '80'
        }
      }
    ]
  }
}

resource natPip 'Microsoft.Network/publicIPAddresses@2024-05-01' = if (useNatGateway) {
  name: 'pip-${namePrefix}-nat-${regionCode}'
  location: location
  tags: tags
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static' }
}

resource nat 'Microsoft.Network/natGateways@2024-05-01' = if (useNatGateway) {
  name: 'ng-${namePrefix}-${regionCode}'
  location: location
  tags: tags
  sku: { name: 'Standard' }
  properties: {
    publicIpAddresses: [{ id: natPip.id }]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-${namePrefix}-${regionCode}'
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: ['10.20.0.0/16'] }
    subnets: [
      {
        name: 'snet-vms'
        properties: {
          addressPrefix: '10.20.1.0/24'
          networkSecurityGroup: { id: nsg.id }
          natGateway: useNatGateway ? { id: nat.id } : null
          // Explicit: no implicit internet egress (ADR 0002).
          defaultOutboundAccess: false
        }
      }
    ]
  }
}

output subnetId string = vnet.properties.subnets[0].id
output asgSshId string = asgSsh.id
output asgWebId string = asgWeb.id
