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
Built by hand in the Azure Portal, to learn the moving parts. On 2026-10-16 the action group and the
rule moved into Bicep so the repo and Azure do not drift (see Moved to Bicep below).

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

### Moved to Bicep (2026-10-16)
The action group and the rule now come from [`infra/monitoring.bicep`](../../infra/monitoring.bicep),
deployed from the owner's Mac. The email address is read from the `ALERT_EMAIL` environment
variable, so it is not in git.

Commands as run (zsh on macOS):

```bash
export ALERT_EMAIL=<owner email>
az deployment group what-if -g rg-azopslab-swc -p infra/monitoring.bicepparam
az deployment group create -g rg-azopslab-swc -p infra/monitoring.bicepparam \
  --name monitoring-baseline-20261016 -o table
az deployment group what-if -g rg-azopslab-swc -p infra/monitoring.bicepparam   # drift check
```

| Step | Result |
|---|---|
| What-if 1 | 1 to create (new action group), 1 to modify (rule). One line showed the `keepalive` tag as `"False"` instead of `"false"`: a template bug, fixed before deploying ([#22](https://github.com/Jiajunhadichen/azure-ops-lab/issues/22)) |
| What-if 2 | Same counts. Rule: action group → `ag-azopslab-email`; status filter `containsAny ["succeeded"]` → `equals "Succeeded"` (the Portal and Bicep forms of the same filter); tags unchanged |
| Deploy | `monitoring-baseline-20261016` Succeeded at 08:25 UTC, Incremental mode (resources not in the template, such as the old action group, are left alone) |
| Email receiver | "You've been added to an Azure Monitor action group" email; no verification code this time (the Portal-built group asked for one; reason not verified) |
| What-if 3, drift check | `2 no change, 2 to ignore`: Azure matches the template |

Re-test through the new action group, Reader assignment created in the CLI:

| Event | Time (UTC) |
|---|---|
| Reader assignment created | 08:32:24 |
| Alert fired, email received | 08:37 (fired 08:37:18) |
| Test Reader assignment removed (by its ID) | ~09:03 |

Result: the alert email arrived through `ag-azopslab-email`. Detection to inbox: about 5 minutes
(third sample).

After the re-test the old action group was deleted, behind a guard that first counts rules still
using it (its name is the only one with `;`):

```bash
REFS=$(az monitor activity-log alert list -g rg-azopslab-swc --query "length([?actions.actionGroups[?contains(actionGroupId, ';')]])" -o tsv)
echo "rules using old group: $REFS"
if [ "$REFS" = "0" ]; then az monitor action-group delete -g rg-azopslab-swc -n 'ag-azops;ab-email'; else echo "STOP: still in use, nothing deleted"; fi
az monitor action-group list -g rg-azopslab-swc --query "[].name" -o tsv
```

Result: `rules using old group: 0`; `ag-azopslab-email` is the only action group left.

Evidence (subscription ID and email masked, role assignment IDs shortened):
- [What-if 1: keepalive bug](../../evidence/monitor-01/2026-10-16-whatif-1-keepalive-bug.png)
- [What-if 2: fixed](../../evidence/monitor-01/2026-10-16-whatif-2-fixed.png)
- [Deploy succeeded](../../evidence/monitor-01/2026-10-16-deploy-succeeded.png)
- [Added to action group email](../../evidence/monitor-01/2026-10-16-added-to-action-group-email.png)
- [What-if 3: drift check](../../evidence/monitor-01/2026-10-16-whatif-3-drift-check.png)
- [Re-test: Reader created](../../evidence/monitor-01/2026-10-16-retest-2-reader-added.png)
- [Re-test: alert email](../../evidence/monitor-01/2026-10-16-retest-2-alert-email.png)
- [Re-test: Reader removed, none left](../../evidence/monitor-01/2026-10-16-retest-2-reader-removed.png)
- [Old action group deleted](../../evidence/monitor-01/2026-10-16-old-action-group-deleted.png)

## What went wrong
- One role assignment fired **two** alerts. Confirmed cause: one operation writes two activity log
  events (same operation ID, status Started, then Succeeded) and the rule accepted all statuses.
  Fixed 2026-10-16 by filtering on status Succeeded; re-test gave one alert and one email (above).
  The Bicep monitoring module ([#19](https://github.com/Jiajunhadichen/azure-ops-lab/pull/19),
  deployed 2026-10-16) sets the same filter. Tracked in [#15](https://github.com/Jiajunhadichen/azure-ops-lab/issues/15).
- Typo in the action group name: it was created as `ag-azops;ab-email` (semicolon instead of `l`).
  Azure resource names cannot be changed after creation. Fixed 2026-10-16: Bicep created
  `ag-azopslab-email`, the rule now points to it, and the typo group was deleted (see Moved to Bicep).
  Lesson: names typed by hand drift; names in code do not. Tracked in [#16](https://github.com/Jiajunhadichen/azure-ops-lab/issues/16).
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
- Test Reader assignments (one on 2026-10-15, two on 2026-10-16): removed. Remaining assignments: inherited
  subscription Owner (one row since 2026-10-16, see below) and the deploy identity's Contributor on
  the resource group.
- Kept: `ag-azopslab-email` and `ar-azopslab-rbac-change` (managed by Bicep since 2026-10-16), as
  the lab's baseline alerting. Deleted: the hand-built `ag-azops;ab-email`.
- Cost: not measured; expected 0 (activity log alerts are free and the email count is far below the
  monthly free allowance).

### Follow-up: duplicate subscription Owner (2026-10-16)
The cleanup check showed the owner's account twice as Owner. `az role assignment list` showed two
separate assignments with the same principal, role (Owner) and scope (subscription), no condition,
both created by the platform at sign-up (2026-07-04 11:29:06 UTC, 79 ms apart, no creator recorded).
Access was identical with one or two; the newer one was removed to keep access reviews clean.

The Portal shows the two rows as identical, so the removal was done in the CLI, picking the newer
assignment by creation time and deleting it by ID only (deleting by assignee, role and scope could
match both and leave the subscription without an Owner):

Commands as run (zsh on macOS):

```bash
SUB="/subscriptions/$(az account show --query id -o tsv)"
N=$(az role assignment list --role Owner --include-inherited --scope "$SUB" --query "length(@)" -o tsv)
KEEP=$(az role assignment list --role Owner --include-inherited --scope "$SUB" --query "sort_by(@, &createdOn)[0].id" -o tsv)
DUP=$(az role assignment list --role Owner --include-inherited --scope "$SUB" --query "sort_by(@, &createdOn)[-1].id" -o tsv)
echo "count:  $N"; echo "keep:   ${KEEP##*/}"; echo "delete: ${DUP##*/}"
if [ "$N" = "2" ] && [ -n "$DUP" ] && [ "$DUP" != "$KEEP" ]; then
  az role assignment delete --ids "$DUP"
else
  echo "STOP: not exactly 2 different Owner assignments, nothing deleted"
fi
az role assignment list --role Owner --include-inherited --scope "$SUB" \
  --query "[].{created:createdOn, isKeep:id=='$KEEP'}" -o table
```

Result: one Owner assignment left, the older one (`isKeep = True`); the Portal shows one Owner row.
Tracked in [#17](https://github.com/Jiajunhadichen/azure-ops-lab/issues/17).
- [Terminal: before, selection, guarded delete, after](../../evidence/monitor-01/2026-10-16-owner-duplicate-removal.png)
- [Portal: one Owner assignment left](../../evidence/monitor-01/2026-10-16-owner-after-removal.png)
