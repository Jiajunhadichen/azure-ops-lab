# azure-ops-lab

A small Azure environment that I build as code, monitor, break on purpose, and recover, with evidence for each step.

> Work in progress. This is a lab with simulated traffic and synthetic data, not a production system.
> Nothing below is marked done until the evidence is in [`evidence/`](evidence/).

| | Result |
|---|---|
| Deploy from scratch (network + 2 VMs) | 1 min 07 s (one run, 2026-10-19, [build-01](labs/build-01-first-vm-deploy/)) |
| Median time to detect a failure (2 alert strategies, 9 drills) | __ min |
| Restore after failure | __ min |
| Monthly lab cost | __ SEK (target: under 500 SEK, excl. VAT) |

Numbers stay as `__` until I have measured them myself.

## The story

| Stage | What it proves | Status |
|---|---|---|
| **Build** | One command creates the network and two Linux VMs from Bicep; one command deletes everything billable. | Deployed and torn down once: 1 min 07 s up, 38 s down, no billable leftovers ([build-01](labs/build-01-first-vm-deploy/)) |
| **Monitor** | Metrics and logs land in Log Analytics; alerts reach me by email. | First alert, deployed from Bicep: role-assignment change to inbox in 3 to 6 min over three tests ([monitor-01](labs/monitor-01-activity-log-alert/)). VM metrics and logs not started |
| **Break** | Scripted failure drills (stopped service, blocked port, full disk) with measured detection time. | Planned |
| **Recover** | Runbooks and backup restores, timed, with a short postmortem for each drill. | Planned |

## Design at a glance

- One resource group in Sweden Central; teardown deletes every lab resource in it and keeps only the free deploy identity and alerting.
- One VNet, one subnet, one NSG. Inbound SSH and HTTP only from my own IP, targeted through application security groups.
- Two Ubuntu 24.04 VMs (D2als_v6, Standard SSD), key-only SSH, Trusted Launch. They run only during lab sessions and are deleted afterwards: the low-cost B-series sizes had no quota in Sweden Central.
- Explicit outbound access: a Standard public IP per VM, or a NAT Gateway behind one parameter ([ADR 0002](docs/adr/0002-vm-outbound-access.md)).
- Every resource is tagged with owner, env, project, expires and keepalive.

## How changes are made

- Every change goes through a pull request using a [template](.github/pull_request_template.md) that asks for risk, cost impact, validation and rollback.
- CI on every PR: full-history secret scan (pinned, checksum-verified gitleaks) and Bicep build and lint ([workflow](.github/workflows/pr-checks.yml)).
- Infrastructure changes are previewed with `what-if` before they are applied.
- Design decisions are recorded as ADRs in [`docs/adr/`](docs/adr/).
- Mistakes and surprises from labs are tracked as [`lab-finding` issues](https://github.com/Jiajunhadichen/azure-ops-lab/issues?q=label%3Alab-finding): what happened, root cause, fix and lesson, closed by the PR that fixes them. Larger incidents get a postmortem in [`ops/postmortems/`](ops/postmortems/).

## Repository map

| Path | Contents |
|---|---|
| [`infra/`](infra/) | Bicep templates (`main.bicep`, `monitoring.bicep`, modules, parameters) |
| [`ops/`](ops/) | Postmortems now; KQL queries and runbooks to come (alert rules live in `infra/monitoring.bicep`) |
| [`drills/`](drills/) | Failure drill scripts, raw data and analysis (empty until the first drill) |
| [`evidence/`](evidence/) | Redacted output and screenshots from real runs |
| [`labs/`](labs/) | AZ-104 practice notes, one folder per lab |
| [`docs/adr/`](docs/adr/) | Architecture decision records |

## AI assistance

I use Claude (Anthropic) as a pair engineer. It drafts templates, workflows and documentation, and runs the Git workflow. I do the Azure hands-on work myself, review every change, and every result in this repo comes from my own runs.
