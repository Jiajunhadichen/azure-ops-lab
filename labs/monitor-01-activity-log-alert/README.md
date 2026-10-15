# Lab monitor-01: Email alert on new role assignments

- Date: 2026-10-15
- Status: In progress (alert fired and email received; cleanup screenshot pending)
- AZ-104 skill: Monitor resources in Azure: configure alert rules, action groups and alert processing rules
- Azure services: Azure Monitor (activity log alert, action group)

## Goal
Get an email when someone creates a role assignment in the lab resource group. Granting yourself
access is a real security event, and this alert can be tested before any VM exists (VMs are still
blocked on quota).

## What I did
Built by hand in the Azure Portal, to learn the moving parts. The action group will move into the
Bicep monitoring module so the repo and Azure do not drift.

1. Action group `ag-azopslab-email` in `rg-azopslab-swc`: region Global, display name `azopslab`,
   one email receiver `email-hadi`, no automated actions, lab tags.
2. Verified the receiver: Azure emailed a one-time code (valid 30 minutes). An unverified email
   receiver gets no alerts.
3. Activity log alert rule `ar-azopslab-rbac-change`:
   - scope: resource group `rg-azopslab-swc`
   - signal: Create role assignment (`Microsoft.Authorization/roleAssignments/write`), category Administrative
   - event level, status and initiator: all
   - action group: `ag-azopslab-email`; region Global; lab tags
4. Test: added a Reader role assignment for myself on the resource group (I am already subscription
   Owner, so effective access did not change; the assignment only creates the event).

## Verification
| Event | Time (UTC) |
|---|---|
| Reader assignment created | 2026-10-15 21:14 |
| Alert fired in Monitor > Alerts | 2026-10-15 21:17 |
| Email received | 2026-10-15 21:17 |

Detection to inbox: about 3 minutes.

Evidence (subscription ID, emails and tenant name masked):
- [Alert rule condition](../../evidence/monitor-01/2026-10-15-alert-rule-condition.png)
- [Fired alerts](../../evidence/monitor-01/2026-10-15-fired-alerts.png)
- [Alert email](../../evidence/monitor-01/2026-10-15-alert-email.png)

## What went wrong
- One role assignment fired **two** alerts. Likely cause: the write is logged twice (status Started,
  then Succeeded) and the rule accepts all statuses. Not yet confirmed. Tuning idea: filter on
  status Succeeded to get one email per change.
- The Monitor > Alerts page looked empty after creating the rule. It lists fired alerts, not rules;
  rules live under Alert rules.

## Decisions
- Activity log alert instead of a log search alert: free, no Log Analytics workspace needed, and the
  signal (a role assignment write) is exactly what we want to catch.
- One shared action group: later alert rules (VM heartbeat, CPU) reuse `ag-azopslab-email`.
- Resource group scope, not subscription: matches the lab boundary.

## Cleanup and cost
- Test Reader assignment: removal pending.
- Kept: the action group and the alert rule, as the lab's baseline alerting.
- Cost: not measured; expected 0 (activity log alerts are free and the email count is far below the
  monthly free allowance).
