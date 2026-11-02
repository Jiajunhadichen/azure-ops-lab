// Two VM alerts, both sent to the email action group from monitoring.bicep:
// - heartbeat lost (log search alert): the agent stopped reporting, e.g. the VM is down
// - CPU high (metric alert): platform metric, works even without the agent
// Deleted on teardown before the VMs, so deleting the VMs does not fire them.

param location string
param namePrefix string
param vmIds array
param workspaceId string
param actionGroupId string
param tags object

// Each VM reports a Heartbeat row every minute. A VM that has been silent for more than 5 minutes
// shows up here. Limit: after 30 minutes of silence it drops out of the query window and the alert
// resolves, although the VM may still be down.
var heartbeatQuery = '''
Heartbeat
| summarize LastHeartbeat = max(TimeGenerated) by Computer
| where LastHeartbeat < ago(5m)
'''

resource heartbeatLost 'Microsoft.Insights/scheduledQueryRules@2021-08-01' = {
  name: 'ar-${namePrefix}-vm-heartbeat-lost'
  location: location // log search alerts live in the workspace region
  tags: tags
  properties: {
    displayName: 'ar-${namePrefix}-vm-heartbeat-lost'
    description: 'A lab VM has sent no heartbeat for more than 5 minutes'
    severity: 1
    enabled: true
    scopes: [workspaceId]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT30M'
    criteria: {
      allOf: [
        {
          query: heartbeatQuery
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          dimensions: [
            { name: 'Computer', operator: 'Include', values: ['*'] } // one alert per VM
          ]
          failingPeriods: { numberOfEvaluationPeriods: 1, minFailingPeriodsToAlert: 1 }
        }
      ]
    }
    autoMitigate: true
    actions: { actionGroups: [actionGroupId] }
  }
}

resource cpuHigh 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'ar-${namePrefix}-vm-cpu-high'
  location: 'global'
  tags: tags
  properties: {
    description: 'Average CPU above 80% for 5 minutes on a lab VM'
    severity: 2
    enabled: true
    scopes: vmIds
    // Required when one rule watches several VMs.
    targetResourceType: 'Microsoft.Compute/virtualMachines'
    targetResourceRegion: location
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria'
      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          name: 'cpu'
          metricNamespace: 'Microsoft.Compute/virtualMachines'
          metricName: 'Percentage CPU'
          timeAggregation: 'Average'
          operator: 'GreaterThan'
          threshold: 80
        }
      ]
    }
    autoMitigate: true
    actions: [
      { actionGroupId: actionGroupId }
    ]
  }
}

output alertNames array = [heartbeatLost.name, cpuHigh.name]
