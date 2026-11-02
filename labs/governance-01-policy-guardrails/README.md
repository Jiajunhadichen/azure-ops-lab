# Lab governance-01: Policy guardrails on the lab resource group

- Date: 2026-11-02
- Status: Done
- AZ-104 skill: Manage Azure subscriptions and governance: implement and manage Azure Policy
- Azure services: Azure Policy (built-in definitions, assignments, non-compliance messages)

## Goal
Make the two cost rules that matter most for this lab enforceable instead of a habit:
resources only in Sweden Central, and VMs only in a short list of small sizes. A wrong template or
a click in the wrong region is then rejected by Azure before anything is billed.

## What I did
In the Azure Portal (Policy > Assignments > Assign policy), both at scope
`Azure subscription 1/rg-azopslab-swc`, effect Deny (built in), enforcement Default:

| Assignment (display name) | Built-in definition | Parameter | Non-compliance message |
|---|---|---|---|
| `pa-azopslab-allowed-locations` | Allowed locations | `swedencentral` | Lab resources must be in Sweden Central. |
| `pa-azopslab-allowed-vm-sizes` | Allowed virtual machine size SKUs | `standard_d2als_v6`, `standard_b2ts_v2`, `standard_b2ats_v2` | Lab VMs must use an approved small size. |

`Standard_D2als_v6` is the size the lab runs today ([build-01](../build-01-first-vm-deploy/)).
The two B-series sizes are on the list in case the open quota request is approved.

Checks in the terminal:

```bash
# Before: nothing assigned
az policy assignment list -g rg-azopslab-swc --query "[].{name:name, def:policyDefinitionId}" -o table
# After: shows display names and parameters
az policy assignment list -g rg-azopslab-swc \
  --query "[].{name:displayName, id:name, params:parameters}" -o json
# Deny tests without creating anything (validate runs the same preflight checks as a deploy)
az deployment group validate -g rg-azopslab-swc -f /tmp/policytest.json -p location=northeurope -o none
az deployment group validate -g rg-azopslab-swc -p infra/main.local.bicepparam -p vmSize=Standard_B1s -o none
az deployment group validate -g rg-azopslab-swc -p infra/main.local.bicepparam -o none
```

## Verification
| Check | Result |
|---|---|
| Assignments on the group before | none |
| Assignments after (2026-11-02 ~13:20 UTC) | 2, parameters and messages as in the table above |
| Deny test, West Europe | Not a policy result: `RequestDisallowedByAzure`, region not accepting new customers (see below) |
| Deny test, North Europe (~13:37 UTC) | `RequestDisallowedByPolicy`, reason "Lab resources must be in Sweden Central."; evaluation shows `northeurope` not in `["swedencentral"]` |
| Deny test, lab template with `vmSize=Standard_B1s` | both VMs `RequestDisallowedByPolicy`, reason "Lab VMs must use an approved small size." |
| Lab template as it is (`Standard_D2als_v6`), `validate` | passes: no output, exit 0. The guardrails do not block the real deployment |

Evidence (crops of the portal blade or terminal only; nothing personal in frame):
- [Before: no assignments](../../evidence/governance-01/2026-11-02-01-policy-list-before.png)
- [Allowed locations definition, next to "Allowed locations for resource groups"](../../evidence/governance-01/2026-11-02-03-allowed-locations-definition.png)
- [Locations: basics](../../evidence/governance-01/2026-11-02-04-locations-basics.png), [parameters](../../evidence/governance-01/2026-11-02-05-locations-parameters.png), [created](../../evidence/governance-01/2026-11-02-06-locations-created.png)
- [VM sizes: parameters](../../evidence/governance-01/2026-11-02-07-vm-sizes-parameters.png), [review](../../evidence/governance-01/2026-11-02-08-vm-sizes-review.png)
- [After: two assignments](../../evidence/governance-01/2026-11-02-09-policy-list-after.png)
- [Deny test in West Europe stopped by Azure, not by the policy](../../evidence/governance-01/2026-11-02-10-validate-westeurope-azure-block.png)
- [Deny test in North Europe stopped by the location policy](../../evidence/governance-01/2026-11-02-11-validate-northeurope-policy-deny.png)
- [Lab template with B1s stopped by the VM size policy](../../evidence/governance-01/2026-11-02-12-validate-b1s-vm-size-deny.png)
- [Lab template with D2als_v6 passes](../../evidence/governance-01/2026-11-02-13-validate-lab-template-passes.png)

The policy error details also contain the subscription ID; the crops stop before those lines.

## What went wrong
- **Guardrails came after the first deploy.** The Policy step was marked optional on 2026-10-13 and
  skipped; VMs were deployed on 2026-10-19 with only the budget alert as a cost control. Found while
  checking the group on 2026-11-02 (`az policy assignment list` returned nothing). Tracked in
  [#27](https://github.com/Jiajunhadichen/azure-ops-lab/issues/27).
- **Scope almost left at the subscription.** The assignment form opens at the subscription
  ([screenshot](../../evidence/governance-01/2026-11-02-02-scope-still-subscription.png)). Caught before
  saving and narrowed to the resource group. At subscription scope the rules would also hit anything
  else in the subscription.
- **The first deny test proved nothing about the policy.** The West Europe test failed with
  `RequestDisallowedByAzure` (the region does not accept this subscription), not
  `RequestDisallowedByPolicy`. The outer message said "policy violation"; only the inner error code
  tells which layer said no. Repeated in North Europe, which accepts the subscription: there the
  policy answered.
- **Name column looked wrong.** `az policy assignment list` showed `a7f3f78d…`, not
  `pa-azopslab-allowed-locations`. The portal stores "Assignment name" as `displayName` and generates
  the resource `name`; query `displayName` to see it, or set `--name` when assigning from the CLI.
- **One message missing at first.** The VM-size assignment was created without a non-compliance
  message and edited afterwards.

## Decisions
- Scope is the lab resource group, not the subscription: the rules are lab-specific.
- Built-in definitions only. "Allowed locations" skips resources whose location is `global`, so the
  action group and the activity log alert are not affected. It does not cover the resource group's
  own location; that is "Allowed locations for resource groups".
- Deny, not Audit: the point is to stop a costly mistake, not to report it afterwards. Deny does not
  touch existing resources; it only blocks new creates and updates.

## Next
- Move both assignments into Bicep, as was done for the alerts in monitor-01, so the portal and the
  repo cannot drift.
- If the quota request is approved, the B-series sizes are already allowed; nothing to change here.

## Cleanup and cost
Policy assignments with built-in definitions cost nothing. Nothing to delete. The deny tests use
`validate`, which creates no resources.
