# Postmortem: Leftover practice resources ran for weeks (Sep–Oct 2026)

- Date written: 2026-10-13
- Status: Closed (cost stopped); follow-up actions tracked below
- Severity: Personal cost impact, no data loss
- Format: blameless. The goal is better guardrails, not blame.

## Summary
While practising for AZ-104 I built several labs (VMs, VNets, NSGs, route tables, disks, Azure Backup) in a pay-as-you-go subscription.
After the labs I did not stop or delete all of them. Five VMs, their disks and backup data kept running in the background for weeks.
Nothing warned me. I found out from the invoice on 2026-10-11.

## Impact
| Period | Cost (Cost Management, before tax) | Invoice |
|---|---|---|
| September 2026 | about 4,548 SEK | 5,682.81 SEK |
| 1–11 October 2026 | about 1,782 SEK (about 141 SEK per day) | not invoiced yet |

Where the money went (September, from Cost Management grouped by resource group and service):
- Running VMs: about 3,822 SEK (84%)
- Storage and managed disks: about 414 SEK
- VNet and public IPs: about 197 SEK
- Azure Backup and restore points: about 103 SEK
- DNS: about 9 SEK

After I explained that this was exam practice, Microsoft Billing Support approved a one-time goodwill credit.

## Timeline
- September 2026: practice labs spread across eight resource groups in three regions (Sweden Central, West US 2, East US). Two of them, a routing lab in Sweden Central and a backup lab in West US 2, account for about 98% of the cost. Several VMs left running after the labs.
- 2026-10-11: invoice arrives; I notice the cost.
- 2026-10-11: stopped all VMs, deleted the resource groups with Azure CLI, then removed the remaining resources.
- 2026-10-11 onwards: contacted Microsoft Billing Support; credit approved.
- 2026-10-13: read-only check shows 0 resource groups and 0 resources.
- 2026-10-13: subscription budget with email alerts created.
- 2026-10-14: daily cost re-checked after the 24–48 h data delay: last charge on 2026-10-11 (about 104 SEK, partial day), nothing from 2026-10-12 on.

## Root causes
1. No budget or cost alert on the subscription, so the first signal was the invoice, weeks later.
2. No cleanup step at the end of a lab. Resources were spread over several resource groups, so there was no single thing to delete.
3. No tags to say who owns a resource or when it should be gone.
4. Running VMs were the main cost, and I did not have the habit of deallocating them when idle.

## What went well
- Once found, cleanup was quick with Azure CLI.
- Cost Management showed exactly which resource groups and services cost the most.

## Action items
| Action | Status |
|---|---|
| Subscription budget with email alerts (actual 50%, 80%, 100%; forecast 100%) | Done 2026-10-13 |
| Cost anomaly alert on the subscription | Planned |
| One resource group per lab; teardown = delete that group | Planned for azure-ops-lab (one-command teardown) |
| Tags on every resource: owner, env, project, expires, keepalive | In Bicep templates |
| Deallocate lab VMs when idle; flag VMs without keepalive | Planned |
| Azure Policy: allowed regions and small VM sizes only | Planned |
| After each lab, check for leftover disks, public IPs, snapshots and backup items | Planned (checklist + script) |

## Lessons
- In a pay-as-you-go lab, the dangerous resource is the one you forgot, not the one you are using.
- A budget alert is the cheapest control there is, and it should exist before the first resource.
- Make cleanup a single command, so that it actually happens.
