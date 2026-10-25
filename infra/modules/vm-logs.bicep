// Log Analytics workspace and the data collection rule (DCR) the VMs' Azure Monitor Agent uses.
// Both are kept on teardown: they cost nothing without incoming data, and keeping the workspace
// lets queries compare sessions (data is kept 30 days).

param location string
param namePrefix string
param regionCode string
param tags object

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'law-${namePrefix}-${regionCode}'
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' } // pay per GB ingested
    retentionInDays: 30
    // Cost guard: ingestion stops for the day at this cap. Two lab VMs send far less.
    workspaceCapping: { dailyQuotaGb: json('0.5') }
  }
}

// What the agent collects: a few performance counters every minute, plus SSH logins and
// system warnings from syslog. The agent also sends a Heartbeat row every minute on its own.
resource dcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: 'dcr-${namePrefix}-vms-${regionCode}'
  location: location
  tags: tags
  kind: 'Linux'
  properties: {
    dataSources: {
      performanceCounters: [
        {
          name: 'perf'
          streams: ['Microsoft-Perf']
          samplingFrequencyInSeconds: 60
          counterSpecifiers: [
            'Processor(*)\\% Processor Time'
            'Memory(*)\\% Used Memory'
            'Logical Disk(*)\\% Used Space'
          ]
        }
      ]
      syslog: [
        {
          name: 'syslog-auth' // SSH logins, sudo
          streams: ['Microsoft-Syslog']
          facilityNames: ['auth', 'authpriv']
          logLevels: ['Info', 'Notice', 'Warning', 'Error', 'Critical', 'Alert', 'Emergency']
        }
        {
          name: 'syslog-system' // service failures, kernel warnings (e.g. a full disk)
          streams: ['Microsoft-Syslog']
          facilityNames: ['daemon', 'kern', 'syslog']
          logLevels: ['Warning', 'Error', 'Critical', 'Alert', 'Emergency']
        }
      ]
    }
    destinations: {
      logAnalytics: [
        { name: 'law', workspaceResourceId: workspace.id }
      ]
    }
    dataFlows: [
      { streams: ['Microsoft-Perf', 'Microsoft-Syslog'], destinations: ['law'] }
    ]
  }
}

output workspaceId string = workspace.id
output dcrId string = dcr.id
