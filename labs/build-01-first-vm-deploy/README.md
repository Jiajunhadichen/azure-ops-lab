# Lab build-01: First VM deploy and teardown

- Date: 2026-10-19
- Status: Done
- AZ-104 skill: Deploy and manage Azure compute resources: create and configure virtual machines, deploy resources by using Bicep; manage VM sizes and quotas
- Azure services: Virtual Machines, Virtual Network, NSG, application security groups, public IPs

## Goal
Deploy the network and two Linux VMs from [`infra/main.bicep`](../../infra/main.bicep) with one
command, check them, and delete everything billable with one command, timing both.

## Why D2als_v6
The low-cost B-series sizes could not be used in Sweden Central: Basv2 quota is 0 (the automatic
increase request was rejected), `Standard_B1s` returns `SkuNotAvailable`, and a support ticket for
B-series quota (opened 2026-10-13) has had no answer. For practice, any small size with quota will do,
so the template switched to a D-series size that runs only during lab sessions.

## What I did
All steps in the terminal (zsh on macOS, Azure CLI). Read-only checks first:

```bash
# 1. Quota: which VM families have a limit above 0 in the region (limit is a string, hence to_number)
az vm list-usage -l swedencentral --query "[?to_number(limit) > to_number('0')].{family:name.value, used:currentValue, limit:limit}" -o table
# 2. Size: restrictions and disk controller type
az vm list-skus -l swedencentral --resource-type virtualMachines --size Standard_D2a \
  --query "[?name=='Standard_D2als_v6' || name=='Standard_D2as_v6' || name=='Standard_D2as_v5'].{name:name, restricted:length(restrictions), disk:capabilities[?name=='DiskControllerTypes'].value|[0]}" -o table
# 3. Price: Azure retail prices API, Linux pay-as-you-go, SEK (full command in the screenshot)
# 4. Image: does Ubuntu 24.04 support NVMe and Trusted Launch?
az vm image show --urn Canonical:ubuntu-24_04-lts:server:latest -l swedencentral \
  --query "features[?name=='DiskControllerTypes' || name=='SecurityType'].{name:name, value:value}" -o table
```

Then deploy, verify and tear down. The parameter file `infra/main.local.bicepparam` is git-ignored;
it holds my IP (for the NSG) and my SSH public key.

```bash
az deployment group what-if -g rg-azopslab-swc -p infra/main.local.bicepparam
time az deployment group create -g rg-azopslab-swc -p infra/main.local.bicepparam --name lab-vms-20261019 -o table
az vm list -g rg-azopslab-swc -d --query "[].{name:name, size:hardwareProfile.vmSize, power:powerState, disk:storageProfile.osDisk.managedDisk.storageAccountType, ctrl:storageProfile.diskControllerType}" -o table
WEBIP=$(az vm show -d -g rg-azopslab-swc -n vm-azopslab-web-swc --query publicIps -o tsv)
ssh -i ~/.ssh/azopslab_ed25519 azureops@$WEBIP 'hostname; lsblk -d -o NAME,SIZE,TYPE; uptime'
./infra/teardown.sh            # dry run
time ./infra/teardown.sh --yes
az resource list -g rg-azopslab-swc --query "[].{type:type, name:name}" -o table
```

## Verification
| Check | Result |
|---|---|
| Quota | `standardDalv6Family` limit 10 vCPUs, regional `cores` limit 10, both 0 used; 2 VMs need 4 |
| Size | `Standard_D2als_v6` not restricted; disk controller NVMe only |
| Price (retail, Linux) | D2als_v6 0.8572, D2as_v6 0.9668, D2as_v5 0.9170 SEK/hour (D2as_v5 has no quota) |
| Image | Ubuntu 24.04: `SCSI, NVMe`, `TrustedLaunchSupported` |
| What-if | 10 to create, 3 to ignore (the identity and the two alerting resources, not in this template) |
| Deploy `lab-vms-20261019` | Succeeded, Incremental, **1 min 07 s** (`time`: 1:06.79), finished 19:36:44 UTC |
| VMs | both `Standard_D2als_v6`, running, `StandardSSD_LRS`, NVMe |
| SSH (key only) | `nvme0n1 32G disk`; up 2 min at 19:38:42 UTC |
| Teardown `--yes` | deleted 2 VMs (OS disks and NICs with them), 2 public IPs, 1 VNet, 1 NSG, 2 ASGs; leftover check all 0, "Clean"; **38 s** (`time`: 37.861) |
| After teardown | the group holds only the 3 kept resources: `id-azopslab-github`, `ar-azopslab-rbac-change`, `ag-azopslab-email` |

One sample each; no typical time is claimed.

Evidence (subscription ID, public IPs and the SSH host key fingerprint redacted):
- [Quota per VM family](../../evidence/build-01/2026-10-19-quota-families.txt)
- [Size and price checks](../../evidence/build-01/2026-10-19-sku-and-price-checks.png)
- [Image features](../../evidence/build-01/2026-10-19-image-features.txt)
- [What-if](../../evidence/build-01/2026-10-19-whatif.txt)
- [Deploy, VM check, SSH, dry run, teardown, resources left](../../evidence/build-01/2026-10-19-deploy-verify-teardown.png)

## What went wrong
- My first quota query guessed family names (`DALSv6`, `DASv6`) and found nothing for them; the real
  name is `standardDalv6Family`. Listing every family with a limit above 0 found it.
- `[?limit > to_number('0')]` crashed with `TypeError: '>' not supported between instances of 'str'
  and 'int'`: `az vm list-usage` returns `limit` as a string. `to_number(limit)` fixed it.
  [`infra/preflight.sh`](../../infra/preflight.sh) now does these checks in one read-only run
  (not yet run against real Azure).
- The teardown dry run listed every resource under "Not in the delete order (handle by hand)".
  Script bug, fixed before the next run; tracked in [#25](https://github.com/Jiajunhadichen/azure-ops-lab/issues/25).
- After `--yes`, the same section briefly listed `asg-azopslab-ssh-swc`, but the leftover check right
  after showed 0 and a later `az resource list` showed only the kept resources. Likely cause (not
  verified): the resource list still showed the ASG while its delete was finishing.
- The what-if output did not list `osDisk.managedDisk.storageAccountType`, although the template sets
  it; the deployed disks are `StandardSSD_LRS` as intended. Reason not verified.
- The prices API returned a second D2as_v5 line (1.8339 SEK/hour). Not explained; not used.

## Decisions
- `Standard_D2als_v6` over D2as_v6 and D2as_v5: cheapest of the three with quota, 2 vCPUs and 4 GiB
  memory are enough for the lab.
- On demand only: deploy at the start of a session, tear down at the end. Left running 24/7, two VMs
  would cost about 1,250 SEK a month (retail price), far over the 500 SEK budget.
- `diskControllerType` follows the size (`NVMe` for `_v6`, `SCSI` otherwise), so B-series sizes still
  work if the quota ticket is approved.

## Cleanup and cost
- Deleted: everything the deploy created. Kept (free): the deploy identity and the alerting baseline.
- Leftover check over the whole subscription: unattached disks 0, unassociated public IPs 0, snapshots 0.
- VMs existed for about 8 minutes. Cost: not measured yet (Cost Management lags by a day or more).
  Estimate from retail prices: under 1 SEK.
