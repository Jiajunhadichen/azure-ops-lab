# Lab monitor-02: VM logs, CPU alert and a first failure drill

- Date: 2026-11-02
- Status: Partly done. CPU drill done; heartbeat drill aborted (see What went wrong)
- AZ-104 skill: Monitor resources in Azure: interpret metrics, configure log settings (data collection rules), query logs with KQL, alert rules and action groups
- Azure services: Azure Monitor (metric alert, log search alert, action group), Log Analytics, Azure Monitor Agent, data collection rule, Virtual Machines

## Goal
Get VM data into Log Analytics and measure how long a real problem takes to reach my inbox.
Two alert strategies:
- a metric alert on CPU (platform metric, no agent needed);
- a log search alert on missing heartbeats (needs the agent; catches a VM that is down).

## What I did
All in the terminal, except the Logs blade and the alert views in the portal. Template:
[`infra/main.bicep`](../../infra/main.bicep) with `enableMonitoring=true` (from #26).

```bash
./infra/preflight.sh                                    # size, quota, price: OK
az deployment group what-if -g rg-azopslab-swc -p infra/main.local.bicepparam
time az deployment group create -g rg-azopslab-swc -p infra/main.local.bicepparam --name lab-vms-20261102-mon -o table
az vm extension list -g rg-azopslab-swc --vm-name vm-azopslab-web-swc -o table
az vm show -g rg-azopslab-swc -n vm-azopslab-web-swc --query identity.type -o tsv
# Drill 1: two busy loops on the web VM for 10 minutes (2 vCPUs)
ssh -i ~/.ssh/azopslab_ed25519 azureops@$WEBIP 'nohup timeout 600 sh -c "yes > /dev/null & yes > /dev/null & wait" >/dev/null 2>&1 & date -u; echo load started'
# Drill 2: stop the app VM's heartbeat
az vm deallocate -g rg-azopslab-swc -n vm-azopslab-app-swc --no-wait; date -u +%H:%M:%S
./infra/teardown.sh            # dry run
time ./infra/teardown.sh --yes
```

KQL in the workspace `law-azopslab-swc` ([saved queries](../../ops/kql/)):

```kusto
Heartbeat
| summarize LastHeartbeat = max(TimeGenerated), Beats = count() by Computer
```

## Verification
Times in UTC, 2026-11-02.

| Step | Result |
|---|---|
| Monitoring deploy `lab-vms-20261102-mon` | Succeeded 14:03:46, **2 min 07 s**; what-if: 8 create, 7 modify (VMs gain an identity; the rest is what-if noise on read-only network properties), no VM re-created |
| Agent and identity | `AzureMonitorLinuxAgent` Succeeded on both VMs; identity `SystemAssigned` |
| First heartbeats | both VMs in `Heartbeat` by 14:08, about 4 min after the deploy |
| Drill 1: CPU load started | 14:11:09 |
| CPU alert fired (`ar-azopslab-vm-cpu-high`, Sev2) | 14:19, 5-min average 92.43% against 80%; email in the same minute |
| Load stopped | ~14:21 |
| CPU alert resolved (auto-mitigate) | 14:27:58, email 14:28 |
| Drill 2: app VM deallocated | 14:26:36; last heartbeat 14:26:08 |
| Heartbeat alert | **not measured**: rule deleted at ~14:31 by teardown, before it could fire |
| Teardown `--yes` | 1 min 03 s; leftover check all 0, "Clean"; workspace and DCR kept by design |

**Time to detect, CPU drill: about 8 minutes** from load start to email (n = 1). It is bounded by the
rule itself (5-minute average, checked every minute) plus 1 to 3 minutes of metric delay.
Recovery to "Resolved": about 7 minutes after the load stopped.

Evidence (terminal and portal crops; subscription ID, public IP, SSH host key and email address
removed):
- [Deploy that used the wrong branch](../../evidence/monitor-02/2026-11-02-01-deploy-wrong-branch.png), [VMs with no identity](../../evidence/monitor-02/2026-11-02-02-vms-running-no-identity.png)
- [Re-deploy: what-if summary and deploy](../../evidence/monitor-02/2026-11-02-03-whatif-redeploy-and-deploy.png), [agent and identity](../../evidence/monitor-02/2026-11-02-04-ama-and-identity.png)
- [First heartbeats](../../evidence/monitor-02/2026-11-02-05-first-heartbeats.png)
- [CPU load started](../../evidence/monitor-02/2026-11-02-06-cpu-load-started.png), [alert email: Fired](../../evidence/monitor-02/2026-11-02-07-cpu-alert-email-fired.png), [alert details](../../evidence/monitor-02/2026-11-02-08-cpu-alert-details.png), [alert email: Resolved](../../evidence/monitor-02/2026-11-02-12-cpu-alert-email-resolved.png)
- [App VM deallocated](../../evidence/monitor-02/2026-11-02-09-app-vm-deallocated.png), [app heartbeat stopped at 14:26](../../evidence/monitor-02/2026-11-02-11-app-heartbeat-stopped.png)
- [Teardown dry run](../../evidence/monitor-02/2026-11-02-10-teardown-dry-run.png), [teardown: Clean](../../evidence/monitor-02/2026-11-02-13-teardown-clean.png)

## What went wrong
- **First deploy came up without monitoring.** `lab-vms-20261102` (13:54) built the VMs and network
  only. Claude had switched the shared working copy to a branch off `main` two minutes earlier, so
  the deploy compiled the template without monitoring; the what-if before it had run on the right
  branch. Fixed with an incremental re-deploy. Lab finding
  [#34](https://github.com/Jiajunhadichen/azure-ops-lab/issues/34).
- **`preflight.sh` said the size was "not offered".** A parsing bug (multi-value `-o tsv` output);
  fixed in #31 ([#30](https://github.com/Jiajunhadichen/azure-ops-lab/issues/30)).
- **Heartbeat drill aborted.** Teardown started about 5 minutes after the app VM stopped. The
  heartbeat rule needs more than 5 minutes of silence plus a 5-minute evaluation cycle, so it was
  deleted before it could fire. A drill ends when the alert arrives, not after a fixed wait.
- **Opened the wrong VM's metrics first** (app instead of web). Kept as a baseline: the idle VM
  stayed near 4%.
- **The new Logs blade opened in "Agent" (AI chat) mode** with no query editor. Switched the toggle
  off and used KQL mode.

## Decisions
- CPU alert on the platform metric, not on agent data: it works even if the agent is broken.
- Heartbeat alert as a log search alert: it is the only one of the two that notices a VM that is
  down.
- Teardown keeps the workspace and the DCR (no data, no charge) so the next session reuses them;
  it deletes the VM alerts first so a dying VM does not page.

## Cleanup and cost
Teardown at ~14:32, "Clean: nothing billable left". The group keeps only the identity, the RBAC
alert, the action group, the workspace and the DCR. VMs ran about 40 minutes (web) and 33 minutes
(app). Estimate from retail prices: about 1.5 SEK for compute; Cost Management lags by a day or
more, so the actual cost is "not measured" yet.

## Next
- Repeat the heartbeat drill and wait for the email before teardown.
- Repeat the CPU drill to get more than one sample before quoting a typical time.
