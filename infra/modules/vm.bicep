// One Ubuntu 24.04 VM with key-only SSH, Trusted Launch, a Standard SSD OS disk
// and (optionally) its own Standard public IP.

param location string
param name string
param subnetId string
param asgIds array
param withPublicIp bool
param vmSize string
param adminUsername string
@secure()
param sshPublicKey string
param tags object

resource pip 'Microsoft.Network/publicIPAddresses@2024-05-01' = if (withPublicIp) {
  name: 'pip-${name}'
  location: location
  tags: tags
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static' }
}

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: 'nic-${name}'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: { id: subnetId }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: withPublicIp ? { id: pip.id } : null
          applicationSecurityGroups: [for id in asgIds: { id: id }]
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    hardwareProfile: { vmSize: vmSize }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: { secureBootEnabled: true, vTpmEnabled: true }
    }
    osProfile: {
      computerName: name
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            { path: '/home/${adminUsername}/.ssh/authorized_keys', keyData: sshPublicKey }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        name: 'osdisk-${name}'
        createOption: 'FromImage'
        diskSizeGB: 32 // E4 tier
        managedDisk: { storageAccountType: 'StandardSSD_LRS' }
        deleteOption: 'Delete' // no orphaned disk when the VM is deleted
      }
    }
    networkProfile: {
      networkInterfaces: [{ id: nic.id, properties: { deleteOption: 'Delete' } }]
    }
    diagnosticsProfile: {
      bootDiagnostics: { enabled: true } // managed storage, used for serial console
    }
  }
}

output name string = vm.name
output publicIp string = withPublicIp ? pip!.properties.ipAddress : ''
