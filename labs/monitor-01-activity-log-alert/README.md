# Lab monitor-01: Email alert on new role assignments

- Date: 2026-10-15
- Status: Done
- AZ-104 skill: Monitor resources in Azure: configure alert rules, action groups and alert processing rules
- Azure services: Azure Monitor (activity log alert, action group)

## Goal
Get an email when someone creates a role assignment in the lab resource group. Granting yourself
access is a real security event, and this alert can be tested before any VM exists (VMs are still
blocked on quota).

## What I did
Built by hand in the Azure Portal, to learn the moving parts. The action group will move into the
Bicep monitoring module so the repo and Azure do not drift.

1. Action group in `rg-azopslab-swc` (intended name `ag-azopslab-email`, see What went wrong):
   region Global, display name `azopslab`,
   one email receiver `email-hadi`, no automated actions, lab tags.
2. Verified the receiver: Azure emailed a one-time code (valid 30 minutes). An unverified email
   receiver gets no alerts.
3. Activity log alert rule `ar-azopslab-rbac-change`:
   - scope: resource group `rg-azopslab-swc`
   - signal: Create role assignment (`Microsoft.Authorization/roleAssignments/write`), category Administrative
   - event level and initiator: all
   - status: all at first; Succeeded only since 2026-10-16 (see What went wrong)
   - action group: the one above; region Global; lab tags
4. Test: added a Reader role assignment for myself on the resource group (I am already subscription
   Owner, so effective access did not change; the assignment only creates the event).

## Verification
| Event | Time (UTC) |
|---|---|
| Reader assignment created | 2026-10-15 21:14 |
| Alert fired in Monitor > Alerts | 2026-10-15 21:17 |
| Email received | 2026-10-15 21:17 |
| Test Reader assignment removed | 2026-10-15 ~21:25 |

Detection to inbox: about 3 minutes.

Evidence (subscription ID, emails and tenant name masked):
- [Action group overview](../../evidence/monitor-01/2026-10-15-action-group-overview.png) (email receiver verified)
- [Alert rule condition](../../evidence/monitor-01/2026-10-15-alert-rule-condition.png)
- [Alert rule overview](../../evidence/monitor-01/2026-10-15-alert-rule-overview.png)
- [Fired alerts](../../evidence/monitor-01/2026-10-15-fired-alerts.png)
- [Alert email](../../evidence/monitor-01/2026-10-15-alert-email.png)
- [Role assignments after cleanup](../../evidence/monitor-01/2026-10-15-role-assignments-after-cleanup.png)

### Re-test after tuning (2026-10-16)
Rule status filter changed to Succeeded only, then the same test repeated.

| Event | Time (UTC) |
|---|---|
| Reader assignment created | 2026-10-16 07:31 |
| Event available in the activity log (submission timestamp) | 07:33 |
| Alert fired, email received | 07:37 |
| Test Reader assignment removed | ~07:50 |

Result: one alert (Monitor > Alerts total went from 2 to 3, status Succeeded) and one email.
No second alert by 07:50. Detection to inbox: about 6 minutes this time, against about 3 on
2026-10-15; two samples, so no typical value is claimed.

Evidence:
- [Root cause: same operation, status Started and Succeeded](../../evidence/monitor-01/2026-10-15-alert-status-started-vs-succeeded.png) (the two alerts from 2026-10-15)
- [Rule condition: status Succeeded](../../evidence/monitor-01/2026-10-16-alert-rule-status-succeeded.png)
- [Fired alerts after re-test](../../evidence/monitor-01/2026-10-16-retest-fired-alerts.png)
- [Alert email](../../evidence/monitor-01/2026-10-16-retest-alert-email.png)
- [Role assignments after cleanup](../../evidence/monitor-01/2026-10-16-retest-reader-removed.png)

## What went wrong
- One role assignment fired **two** alerts. Confirmed cause: one operation writes two activity log
  events (same operation ID, status Started, then Succeeded) and the rule accepted all statuses.
  Fixed 2026-10-16 by filtering on status Succeeded; re-test gave one alert and one email (above).
  The Bicep monitoring module in [#19](https://github.com/Jiajunhadichen/azure-ops-lab/pull/19)
  (not deployed yet) sets the same filter. Tracked in [#15](https://github.com/Jiajunhadichen/azure-ops-lab/issues/15).
- Typo in the action group name: it was created as `ag-azops;ab-email` (semicolon instead of `l`).
  Azure resource names cannot be changed after creation. It works, so it stays for now; the Bicep
  monitoring module will create `ag-azopslab-email`, the rule will point to it, and the typo group
  will be deleted. Lesson: names typed by hand drift; names in code do not. Tracked in [#16](https://github.com/Jiajunhadichen/azure-ops-lab/issues/16).
- The Monitor > Alerts page looked empty after creating the rule. It lists fired alerts, not rules;
  rules live under Alert rules.
- Open question: on 2026-10-16 the subscription Activity log view (last 24 hours) showed the
  `Delete role assignment` event from 2026-10-15 but no `Create role assignment` row, although the
  alert details show both create events. Not explained yet.

## Decisions
- Activity log alert instead of a log search alert: free, no Log Analytics workspace needed, and the
  signal (a role assignment write) is exactly what we want to catch.
- One shared action group: later alert rules (VM heartbeat, CPU) reuse it.
- Resource group scope, not subscription: matches the lab boundary.

## Cleanup and cost
- Test Reader assignments (2026-10-15 and 2026-10-16): removed. Remaining assignments: inherited
  subscription Owner (two rows, see [#17](https://github.com/Jiajunhadichen/azure-ops-lab/issues/17))
  and the deploy identity's Contributor on the resource group.
- Kept: the action group and the alert rule, as the lab's baseline alerting.
- Cost: not measured; expected 0 (activity log alerts are free and the email count is far below the
  monthly free allowance).
