// Lab alerting baseline: one email action group and one activity log alert on new role assignments.
// Deployed on its own into rg-azopslab-swc (no VMs needed). VM alerts will be added here later.
// Replaces the hand-built action group from lab monitor-01 (see issues #15 and #16).
//
// Deploy from the repo root (the email stays in your shell, not in git):
//   export ALERT_EMAIL='you@example.com'
//   az deployment group what-if -g rg-azopslab-swc -p infra/monitoring.bicepparam
//   az deployment group create  -g rg-azopslab-swc -p infra/monitoring.bicepparam
targetScope = 'resourceGroup'

@description('Email address that receives alerts. Passed at deploy time, never committed.')
param alertEmail string

@description('Tag: who owns these resources.')
param owner string

@description('Tag: date (YYYY-MM-DD) after which the resources may be deleted.')
param expires string

@description('Tag: true keeps the resources past the expires date.')
param keepalive bool = false

var workload = 'azopslab'
var tags = {
  owner: owner
  env: 'lab'
  project: 'azure-ops-lab'
  expires: expires
  keepalive: string(keepalive)
}

// Action groups and activity log alerts are global resources.
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-${workload}-email'
  location: 'Global'
  tags: tags
  properties: {
    groupShortName: workload // max 12 characters; shown in the email
    enabled: true
    emailReceivers: [
      {
        name: 'email-owner'
        emailAddress: alertEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

// Fires once per new role assignment in this resource group.
// status == Succeeded: without it, one change fires twice (Started, then Succeeded). Issue #15.
resource rbacChangeAlert 'Microsoft.Insights/activityLogAlerts@2020-10-01' = {
  name: 'ar-${workload}-rbac-change'
  location: 'Global'
  tags: tags
  properties: {
    description: 'Someone created a role assignment in the lab resource group'
    enabled: true
    scopes: [
      resourceGroup().id
    ]
    condition: {
      allOf: [
        { field: 'category', equals: 'Administrative' }
        { field: 'operationName', equals: 'Microsoft.Authorization/roleAssignments/write' }
        { field: 'status', equals: 'Succeeded' }
      ]
    }
    actions: {
      actionGroups: [
        { actionGroupId: actionGroup.id }
      ]
    }
  }
}

output actionGroupName string = actionGroup.name
output alertRuleName string = rbacChangeAlert.name
